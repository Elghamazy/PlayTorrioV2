FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache python3 make g++

COPY package.json .
RUN npm install --production

COPY src/ ./src/

EXPOSE 7860

ENV PORT=7860
ENV NODE_ENV=production

CMD ["node", "src/server.js"]