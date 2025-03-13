# GitHub Challenges Guide

This guide provides detailed instructions for completing the GitHub-focused challenges in the ARO Migration Hackathon.

## Challenge 3: GitHub Copilot Integration

GitHub Copilot is an AI pair programmer that helps you write code faster and with less work. In this challenge, you'll use Copilot to add new features to the application.

### Setting Up GitHub Copilot

1. **Install GitHub Copilot extension**:
   - In VS Code: Install the GitHub Copilot extension from the marketplace
   - In JetBrains IDEs: Install the GitHub Copilot plugin
   - In Visual Studio: Install the GitHub Copilot extension

2. **Sign in and authorize**:
   - Sign in with your GitHub account
   - Authorize GitHub Copilot to access your account

3. **Verify installation**:
   - Start typing code and watch for Copilot suggestions appearing in ghost text
   - Press Tab to accept suggestions

### Example Feature: Adding Task Search Functionality

1. **Frontend Component**: Use Copilot to help create a search component

   Start by typing:
   ```javascript
   // Create a search component for filtering tasks
   ```

   Let Copilot suggest the component implementation and enhance it as needed.

2. **Backend API Endpoint**: Add a search endpoint to the backend API

   Start by typing:
   ```javascript
   // Add search endpoint to filter tasks based on title or description
   ```

   Work with Copilot to implement the search functionality.

3. **Document Your Process**:
   - Take screenshots of interesting Copilot suggestions
   - Note where Copilot was most helpful
   - Document any limitations or cases where you needed to significantly modify Copilot's suggestions

## Challenge 4: GitHub AI Models

GitHub AI Models can help you understand, explain, and improve your code. In this challenge, you'll leverage these AI capabilities for various tasks.

### Using GitHub AI Models

1. **Access GitHub AI Models**:
   - In a GitHub repository, look for the "Ask on this code" feature
   - Use GitHub AI within pull request comments
   - Use AI summarization for PRs

2. **Code Explanation**:
   Ask GitHub AI to explain complex parts of the codebase:
   
   ```
   @github Can you explain how the task status update logic works in this code?
   ```

3. **Documentation Generation**:
   Ask GitHub AI to generate documentation for undocumented functions:
   
   ```
   @github Please generate JSDoc comments for this function
   ```

4. **Code Improvement**:
   Ask GitHub AI for optimization suggestions:
   
   ```
   @github How could I optimize this database query for better performance?
   ```

5. **Implementation**:
   - Choose at least one suggestion from GitHub AI
   - Implement the improvement
   - Document the before/after comparison

## Challenge 5: GitHub Advanced Security

GitHub Advanced Security offers powerful tools to identify and fix security vulnerabilities in your code.

### Setting Up GitHub Advanced Security

1. **Enable Advanced Security features**:
   - Go to your repository settings
   - Navigate to "Security & analysis"
   - Enable:
     - Dependency graph
     - Dependabot alerts
     - Dependabot security updates
     - Code scanning
     - Secret scanning

2. **Configure CodeQL Analysis**:
   Create a workflow file at `.github/workflows/codeql-analysis.yml`:

   ```yaml
   name: "CodeQL"

   on:
     push:
       branches: [ main ]
     pull_request:
       branches: [ main ]
     schedule:
       - cron: '17 19 * * 0'

   jobs:
     analyze:
       name: Analyze
       runs-on: ubuntu-latest
       permissions:
         actions: read
         contents: read
         security-events: write

       strategy:
         fail-fast: false
         matrix:
           language: [ 'javascript' ]

       steps:
       - name: Checkout repository
         uses: actions/checkout@v3

       - name: Initialize CodeQL
         uses: github/codeql-action/init@v2
         with:
           languages: ${{ matrix.language }}

       - name: Perform CodeQL Analysis
         uses: github/codeql-action/analyze@v2
   ```

3. **Add Dependency Scanning to CI/CD Pipeline**:
   Add Dependabot configuration at `.github/dependabot.yml`:

   ```yaml
   version: 2
   updates:
     - package-ecosystem: "npm"
       directory: "/on-prem-app/backend"
       schedule:
         interval: "weekly"
       open-pull-requests-limit: 10

     - package-ecosystem: "npm"
       directory: "/on-prem-app/frontend"
       schedule:
         interval: "weekly"
       open-pull-requests-limit: 10
   ```

4. **Add Secret Scanning to CI/CD Pipeline**:
   Configure your workflow to detect leaked secrets:

   ```yaml
   - name: Secret Scanning
     uses: gitleaks/gitleaks-action@v2
     env:
       GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```

5. **Address Security Issues**:
   - Review and fix any security vulnerabilities identified
   - Update dependencies with known vulnerabilities
   - Remove or secure any exposed secrets
   - Document the security improvements you've made
