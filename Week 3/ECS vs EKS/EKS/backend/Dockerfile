FROM node:18-alpine

# Security: Set the working directory and ensure it's owned by the node user
WORKDIR /usr/src/app

# Copy dependency manifests first to leverage Docker cache
COPY package*.json ./

# Install only production dependencies
RUN npm install --only=production

# Copy source code and change ownership
COPY . .
# Note: In a professional setup, use a multi-stage build even for backend 
# if you have a build/transpilation step (like TypeScript).

# Security: Switch to a non-root user
USER node

EXPOSE 8080
CMD [ "node", "index.js" ]