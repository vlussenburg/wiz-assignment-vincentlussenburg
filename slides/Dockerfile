# Stage 1: Generate architecture diagram with Python diagrams library
FROM python:3.11-slim AS diagrams-stage
RUN apt-get update && \
    apt-get install -y --no-install-recommends graphviz && \
    rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir diagrams
WORKDIR /build
COPY diagrams/architecture.py .
RUN python architecture.py

# Stage 2: Generate Mermaid diagrams
FROM node:20 AS mermaid-stage
RUN apt-get update && \
    apt-get install -y --no-install-recommends chromium && \
    rm -rf /var/lib/apt/lists/*
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
WORKDIR /build
COPY diagrams/*.mmd ./
RUN echo '{"executablePath":"/usr/bin/chromium","args":["--no-sandbox","--disable-setuid-sandbox"]}' > puppeteer.json
RUN npx --yes @mermaid-js/mermaid-cli \
    -i pipeline.mmd -o pipeline.png \
    -p puppeteer.json -b transparent -w 1200 -H 800
RUN npx --yes @mermaid-js/mermaid-cli \
    -i attack-chain.mmd -o attack-chain.png \
    -p puppeteer.json -b transparent -w 1200 -H 900

# Stage 3: Render slides with Marp
FROM node:20 AS marp-stage
RUN apt-get update && \
    apt-get install -y --no-install-recommends chromium && \
    rm -rf /var/lib/apt/lists/*
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
# Wrapper script runs Chromium with --no-sandbox (required as root in Docker)
RUN printf '#!/bin/sh\nexec /usr/bin/chromium --no-sandbox "$@"\n' \
    > /usr/local/bin/chromium-no-sandbox && \
    chmod +x /usr/local/bin/chromium-no-sandbox
ENV CHROME_PATH=/usr/local/bin/chromium-no-sandbox
RUN npm install -g @marp-team/marp-cli
WORKDIR /build
COPY slides.md .
COPY title-bg.svg .
RUN mkdir -p output/images
COPY --from=diagrams-stage /build/architecture.png ./output/images/
COPY --from=mermaid-stage /build/pipeline.png ./output/images/
COPY --from=mermaid-stage /build/attack-chain.png ./output/images/
RUN marp slides.md --html --allow-local-files -o output/slides.html
RUN marp slides.md --html --allow-local-files --pptx -o output/slides.pptx || \
    echo "PPTX generation skipped (Chromium issue); HTML is available"
RUN cp title-bg.svg output/

# Final: serve via HTTP (file:// can't load relative assets)
FROM nginx:alpine
COPY --from=marp-stage /build/output/ /usr/share/nginx/html/
EXPOSE 80
CMD ["sh", "-c", "cp -r /usr/share/nginx/html/* /output/ 2>/dev/null; exec nginx -g 'daemon off;'"]
