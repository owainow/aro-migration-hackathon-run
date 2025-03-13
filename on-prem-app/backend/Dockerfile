FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3001

# Change this line to explicitly use the src path
CMD ["node", "src/server.js"]