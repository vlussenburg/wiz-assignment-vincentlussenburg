FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install && npm ci --omit=dev

COPY . .

# Required by Wiz exercise — must contain your name
COPY wizexercise.txt /wizexercise.txt

EXPOSE 3000

CMD ["node", "server.js"]
