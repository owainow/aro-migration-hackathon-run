#!/bin/bash
# Interactive script to set up Azure resources for ARO Migration Hackathon
# This script will create:
# - Resource Group
# - Virtual Network and Subnets
# - Azure Red Hat OpenShift Cluster
# - Azure Container Registry

set -e

# Text formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BOLD}Welcome to the ARO Migration Hackathon Setup!${NC}"
echo -e "This script will help you set up the necessary Azure resources."
echo -e "You'll be prompted for information along the way.\n"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${YELLOW}Azure CLI is not installed. Please install it first.${NC}"
    echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Clear any cached configurations
echo -e "${BLUE}Clearing any stale Azure CLI configurations...${NC}"
az config unset defaults.group
az config unset defaults.location
az config unset defaults.vnet
az config unset defaults.subnet

# Always prompt for Azure login
echo -e "${BLUE}Please log in to your Azure account...${NC}"
az login
if [ $? -ne 0 ]; then
    echo "Failed to log in to Azure. Please try again."
    exit 1
fi


# Prompt for resource group name and location
echo -e "\n${BOLD}Enter a name for your resource group:${NC}"
echo "Default: aro-hackathon-rg"
read -p "> " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-aro-hackathon-rg}

echo -e "\n${BOLD}Enter the Azure region to deploy to:${NC}"
echo "Examples: uksouth, westeurope, australiaeast"
echo "Default: uksouth"  # Changed default to eastus which often has better availability
read -p "> " LOCATION
LOCATION=${LOCATION:-uksouth}

# Register resource providers BEFORE creating resources
echo -e "\n${BLUE}Registering necessary resource providers...${NC}"
az provider register -n Microsoft.Network --wait --output none
az provider register -n Microsoft.RedHatOpenShift --wait --output none
az provider register -n Microsoft.Compute --wait --output none
az provider register -n Microsoft.Storage --wait --output none
az provider register -n Microsoft.Authorization --wait --output none
az provider register -n Microsoft.ContainerRegistry --wait --output none

# Check subscription limits and region availability
echo -e "${BLUE}Verifying subscription settings for region ${LOCATION}...${NC}"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo -e "Using subscription: ${BOLD}$SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)${NC}"

# Create resource group
echo -e "\n${BLUE}Creating resource group ${RESOURCE_GROUP} in ${LOCATION}...${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none || {
  echo -e "${RED}Failed to create resource group. Please check your permissions and region availability.${NC}"
  exit 1
}

# Wait longer for resource group to be fully provisioned
echo -e "${BLUE}Waiting for resource group to be fully provisioned...${NC}"
for i in {1..15}; do
  echo "Checking resource group availability ($i of 15)..."
  if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
    echo -e "${GREEN}Resource group is now fully provisioned.${NC}"
    # Extra buffer time
    sleep 15
    break
  fi
  sleep 5
done

# Prompt for cluster name
echo -e "\n${BOLD}Enter a name for your ARO cluster:${NC}"
echo "Default: aro-cluster"
read -p "> " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-aro-cluster}

# Setting up variables for networking
VNET_NAME="${CLUSTER_NAME}-vnet"
MASTER_SUBNET="${CLUSTER_NAME}-master-subnet"
WORKER_SUBNET="${CLUSTER_NAME}-worker-subnet"

# Improved virtual network creation with exponential backoff
create_vnet_with_retries() {
  local retries=5
  local wait_time=15
  
  echo -e "${BLUE}Creating virtual network ${VNET_NAME} with retries...${NC}"
  for i in $(seq 1 $retries); do
    echo "Attempt $i of $retries..."
    
    if az network vnet create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$VNET_NAME" \
      --address-prefix 10.0.0.0/16; then
      
      echo -e "${GREEN}Successfully created virtual network.${NC}"
      return 0
    else
      echo -e "${YELLOW}VNet creation attempt $i failed. Waiting before retry...${NC}"
      sleep $wait_time
      wait_time=$((wait_time * 2))  # Exponential backoff
    fi
  done
  
  echo -e "${RED}Failed to create virtual network after $retries attempts.${NC}"
  return 1
}

# Improved subnet creation with exponential backoff
create_subnet_with_retries() {
  local subnet_name="$1"
  local address_prefix="$2"
  local retries=5
  local wait_time=20
  
  echo -e "${BLUE}Creating subnet ${subnet_name} with retries...${NC}"
  for i in $(seq 1 $retries); do
    echo "Attempt $i of $retries..."
    
    # First verify the VNet still exists
    if ! az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --output none 2>/dev/null; then
      echo -e "${YELLOW}VNet not found, waiting before retry...${NC}"
      sleep $wait_time
      continue
    fi
    
    if az network vnet subnet create \
      --resource-group "$RESOURCE_GROUP" \
      --vnet-name "$VNET_NAME" \
      --name "$subnet_name" \
      --address-prefixes "$address_prefix" \
      --service-endpoints Microsoft.ContainerRegistry; then
      
      echo -e "${GREEN}Successfully created subnet ${subnet_name}.${NC}"
      
      # Now verify the subnet is actually there
      for j in {1..5}; do
        echo "Verifying subnet existence (attempt $j of 5)..."
        if az network vnet subnet show \
          --resource-group "$RESOURCE_GROUP" \
          --vnet-name "$VNET_NAME" \
          --name "$subnet_name" --output none 2>/dev/null; then
          
          echo -e "${GREEN}Subnet ${subnet_name} verified.${NC}"
          return 0
        fi
        sleep 5
      done
      
      echo -e "${YELLOW}Could not verify subnet after creation. Continuing anyway.${NC}"
      return 0
    else
      echo -e "${YELLOW}Subnet creation attempt $i failed. Waiting before retry...${NC}"
      sleep $wait_time
      wait_time=$((wait_time * 2))  # Exponential backoff
    fi
  done
  
  echo -e "${RED}Failed to create subnet ${subnet_name} after $retries attempts.${NC}"
  return 1
}

# Create VNet with retries
if ! create_vnet_with_retries; then
  echo -e "${RED}Virtual network creation ultimately failed. Exiting.${NC}"
  exit 1
fi

# Ensure extra propagation time after successful VNet creation
echo -e "${BLUE}Adding extra delay to ensure VNet propagation...${NC}"
sleep 60

# Create master subnet with retries
if ! create_subnet_with_retries "$MASTER_SUBNET" "10.0.0.0/23"; then
  echo -e "${RED}Master subnet creation ultimately failed. Exiting.${NC}"
  exit 1
fi

# Extra propagation time between subnet creations
echo -e "${BLUE}Adding delay between subnet creations...${NC}"
sleep 30

# Create worker subnet with retries
if ! create_subnet_with_retries "$WORKER_SUBNET" "10.0.2.0/23"; then
  echo -e "${RED}Worker subnet creation ultimately failed. Exiting.${NC}"
  exit 1
fi

# Extra propagation time after subnet creation
echo -e "${BLUE}Adding delay after subnet creation...${NC}"
sleep 30

# Create a function for subnet updates with retries
update_subnet_with_retries() {
  local subnet_name="$1"
  local retries=5
  local wait_time=20
  
  echo -e "${BLUE}Updating subnet ${subnet_name} with retries...${NC}"
  for i in $(seq 1 $retries); do
    echo "Attempt $i of $retries..."
    
    # First verify the VNet and subnet still exist
    if ! az network vnet subnet show \
         --resource-group "$RESOURCE_GROUP" \
         --vnet-name "$VNET_NAME" \
         --name "$subnet_name" --output none 2>/dev/null; then
      echo -e "${YELLOW}Subnet not found, waiting before retry...${NC}"
      sleep $wait_time
      continue
    fi
    
    if az network vnet subnet update \
      --name "$subnet_name" \
      --resource-group "$RESOURCE_GROUP" \
      --vnet-name "$VNET_NAME" \
      --disable-private-link-service-network-policies true \
      --output none; then
      
      echo -e "${GREEN}Successfully updated subnet ${subnet_name}.${NC}"
      return 0
    else
      echo -e "${YELLOW}Subnet update attempt $i failed. Waiting before retry...${NC}"
      sleep $wait_time
      wait_time=$((wait_time * 2))  # Exponential backoff
    fi
  done
  
  echo -e "${RED}Failed to update subnet ${subnet_name} after $retries attempts.${NC}"
  return 1
}

# Add a longer delay before trying subnet updates
echo -e "${BLUE}Adding extra delay before subnet updates...${NC}"
sleep 60

# Use the function for subnet updates
update_subnet_with_retries "$MASTER_SUBNET"

# Prompt for user initials to create unique ACR name
echo -e "\n${BOLD}Enter your initials (2-3 characters):${NC}"
echo "These will be used to make your ACR name unique"
read -p "> " USER_INITIALS
USER_INITIALS=${USER_INITIALS:-user}

# Generate ACR name - remove hyphens and combine with initials
CLEAN_CLUSTER_NAME=$(echo "${CLUSTER_NAME}" | tr -d '-')
DEFAULT_ACR_NAME="${USER_INITIALS}${CLEAN_CLUSTER_NAME}acr"
DEFAULT_ACR_NAME=$(echo "$DEFAULT_ACR_NAME" | tr '[:upper:]' '[:lower:]')

# Prompt for ACR name
echo -e "\n${BOLD}Enter a name for your Azure Container Registry:${NC}"
echo "Must be globally unique, use only lowercase letters and numbers (no hyphens)"
echo "Default: ${DEFAULT_ACR_NAME}"
read -p "> " ACR_NAME
ACR_NAME=${ACR_NAME:-${DEFAULT_ACR_NAME}}
ACR_NAME=$(echo "$ACR_NAME" | tr '[:upper:]' '[:lower:]' | tr -d '-')

# Validate ACR name (only alphanumeric characters allowed)
if [[ ! "$ACR_NAME" =~ ^[a-z0-9]+$ ]]; then
    echo -e "${YELLOW}Warning: Invalid characters removed from ACR name.${NC}"
    ACR_NAME=$(echo "$ACR_NAME" | tr -cd 'a-z0-9')
fi

# Create ACR
echo -e "\n${BLUE}Creating Azure Container Registry ${ACR_NAME}...${NC}"
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Standard \
  --admin-enabled true \
  --output none

# Ask if the user wants to create the ARO cluster (it takes time)
echo -e "\n${BOLD}Do you want to create the ARO cluster now? This will take 30-40 minutes.${NC}"
echo "If you choose no, instructions will be provided for creating it later."
echo "1) Yes, create it now"
echo "2) No, I'll create it later"
read -p "> " CREATE_CLUSTER_CHOICE

if [ "$CREATE_CLUSTER_CHOICE" == "1" ]; then
    echo -e "\n${BLUE}Refreshing authentication for ARO cluster creation...${NC}"
    echo -e "${YELLOW}You will need to log in again with an account that has Owner or Contributor role.${NC}"
    
    # Force a new login to get a fresh token with the necessary permissions
    az account clear
    az login
    
    # Re-select subscription in case it changed during re-login
    echo -e "${BLUE}Setting the subscription again...${NC}"
    az account set --subscription "$SUBSCRIPTION_ID"
    
    # Add after re-login - Verify VNet still exists and refresh Azure cache
    echo -e "\n${BLUE}Verifying network resources after re-login...${NC}"
    echo -e "${YELLOW}Adding extra delay to ensure resources are visible...${NC}"
    sleep 90

    # Force resource refresh by listing resources
    echo -e "${BLUE}Refreshing resource cache...${NC}"
    az resource list --resource-group "$RESOURCE_GROUP" --output none

    # Explicitly check for VNet by name
    echo -e "${BLUE}Checking for virtual network ${VNET_NAME}...${NC}"
    for i in {1..5}; do
      echo "Attempt $i of 5..."
      if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --output none; then
        echo -e "${GREEN}Virtual network found. Proceeding with ARO cluster creation.${NC}"
        break
      else
        echo -e "${YELLOW}Virtual network not found. Waiting before retry...${NC}"
        sleep 30
        
        # Try to refresh resource cache differently
        az group show --name "$RESOURCE_GROUP" --output none
        az network vnet list --resource-group "$RESOURCE_GROUP" --output none
      fi
      
      if [ $i -eq 5 ]; then
        echo -e "${RED}Could not verify virtual network after multiple attempts.${NC}"
        echo -e "${YELLOW}You may need to check the Azure portal to confirm resources exist.${NC}"
        echo -e "${YELLOW}Attempting to proceed anyway...${NC}"
      fi
    done
    
    echo -e "${BLUE}Retrieving and saving full resource IDs...${NC}"
    VNET_ID=$(az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --query id -o tsv)
    MASTER_SUBNET_ID=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$MASTER_SUBNET" --query id -o tsv)
    WORKER_SUBNET_ID=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$WORKER_SUBNET" --query id -o tsv)

    echo -e "${BLUE}Resource IDs:${NC}"
    echo "VNET_ID: $VNET_ID"
    echo "MASTER_SUBNET_ID: $MASTER_SUBNET_ID" 
    echo "WORKER_SUBNET_ID: $WORKER_SUBNET_ID"

    echo -e "\n${BLUE}Creating ARO cluster using resource IDs...${NC}"

    # Use full resource IDs instead of names
    az aro create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CLUSTER_NAME" \
      --vnet "$VNET_ID" \
      --master-subnet "$MASTER_SUBNET_ID" \
      --worker-subnet "$WORKER_SUBNET_ID" \
      --master-vm-size Standard_D8s_v3 \
      --worker-vm-size Standard_D4s_v3

    # Get ARO cluster credentials and information
    echo -e "\n${GREEN}Getting ARO cluster credentials...${NC}"
    CLUSTER_CREDS=$(az aro list-credentials \
      --name "$CLUSTER_NAME" \
      --resource-group "$RESOURCE_GROUP")
    
    ADMIN_USERNAME=$(echo $CLUSTER_CREDS | jq -r .kubeadminUsername)
    ADMIN_PASSWORD=$(echo $CLUSTER_CREDS | jq -r .kubeadminPassword)
    
    CONSOLE_URL=$(az aro show \
      --name "$CLUSTER_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query "consoleProfile.url" -o tsv)
    
    API_URL=$(az aro show \
      --name "$CLUSTER_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query apiserverProfile.url -o tsv)
    
    echo -e "\n${GREEN}ARO Cluster created successfully!${NC}"
    echo -e "Console URL: ${BOLD}$CONSOLE_URL${NC}"
    echo -e "API Server URL: ${BOLD}$API_URL${NC}"
    echo -e "Admin Username: ${BOLD}$ADMIN_USERNAME${NC}"
    echo -e "Admin Password: ${BOLD}$ADMIN_PASSWORD${NC}"
    
    echo -e "\n${BOLD}To connect using OpenShift CLI:${NC}"
    echo "oc login $API_URL -u $ADMIN_USERNAME -p $ADMIN_PASSWORD"
else
    echo -e "\n${YELLOW}Skipping ARO cluster creation.${NC}"
    echo -e "To create the ARO cluster later, run the following command:"
    echo "az aro create \\"
    echo "  --resource-group $RESOURCE_GROUP \\"
    echo "  --name $CLUSTER_NAME \\"
    echo "  --vnet $VNET_NAME \\"
    echo "  --master-subnet $MASTER_SUBNET \\"
    echo "  --worker-subnet $WORKER_SUBNET \\"
    echo "  --pull-secret @pull-secret.txt"
fi

# Get ACR credentials
echo -e "\n${BLUE}Getting ACR credentials...${NC}"
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv)
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)

# Save environment variables to file
echo -e "\n${BLUE}Saving environment variables to .env file...${NC}"
cat > .env << EOF
# ARO Hackathon Environment Variables
# Created on $(date)

# Azure Resources
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
CLUSTER_NAME=$CLUSTER_NAME
ACR_NAME=$ACR_NAME

# Azure Container Registry
REGISTRY_URL=$ACR_LOGIN_SERVER
REGISTRY_USERNAME=$ACR_USERNAME
REGISTRY_PASSWORD=$ACR_PASSWORD

# ARO Cluster
$([ "$CREATE_CLUSTER_CHOICE" == "1" ] && echo "OPENSHIFT_API_URL=$API_URL")
$([ "$CREATE_CLUSTER_CHOICE" == "1" ] && echo "OPENSHIFT_CONSOLE_URL=$CONSOLE_URL")
$([ "$CREATE_CLUSTER_CHOICE" == "1" ] && echo "OPENSHIFT_USERNAME=$ADMIN_USERNAME")
$([ "$CREATE_CLUSTER_CHOICE" == "1" ] && echo "OPENSHIFT_PASSWORD=$ADMIN_PASSWORD")
EOF

echo -e "\n${GREEN}Setup completed successfully!${NC}"
echo -e "Container registry details:"
echo -e "  Registry URL: ${BOLD}$ACR_LOGIN_SERVER${NC}"
echo -e "  Username: ${BOLD}$ACR_USERNAME${NC}"
echo -e "  Password: ${BOLD}$ACR_PASSWORD${NC}"

echo -e "\n${BOLD}To log in to your container registry:${NC}"
echo "docker login $ACR_LOGIN_SERVER -u $ACR_USERNAME -p $ACR_PASSWORD"

echo -e "\n${BOLD}Next steps:${NC}"
echo "1. Use docker-compose to run and test the application locally"
echo "2. Complete the migration challenges outlined in the hackathon guide"
echo -e "\nEnvironment variables have been saved to: ${BOLD}.env${NC}"
echo "You can load them using: source .env"