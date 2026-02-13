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

# Stage 3: Convert asciinema cast to animated SVG
FROM node:20-slim AS asciinema-stage
RUN npm install -g svg-term-cli
WORKDIR /build
COPY demo/attack-chain.cast .
RUN svg-term --in attack-chain.cast --out attack-chain-demo.svg \
    --window --width 90 --height 18 \
    --from 0 --padding 5 \
    --term iterm2 --profile "Builtin Dark"

# Stage 4: Generate slide backgrounds via Ideogram API
FROM python:3.11-slim AS backgrounds-stage
WORKDIR /build
COPY generate-backgrounds.py .
RUN --mount=type=secret,id=env,target=/run/secrets/.env \
    export $(grep IDEOGRAM_API_KEY /run/secrets/.env) && \
    python generate-backgrounds.py

# Stage 5: Generate QR codes for download links
FROM python:3.11-slim AS qrcode-stage
RUN apt-get update && \
    apt-get install -y --no-install-recommends fonts-dejavu-core && \
    rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir qrcode[pil]
WORKDIR /build
COPY generate-qrcodes.py .
RUN python generate-qrcodes.py

# Stage 6: Render slides with Marp
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
RUN mkdir -p output/images output/backgrounds output/qr
COPY --from=diagrams-stage /build/architecture.png ./output/images/
COPY --from=mermaid-stage /build/pipeline.png ./output/images/
COPY --from=mermaid-stage /build/attack-chain.png ./output/images/
COPY --from=backgrounds-stage /build/backgrounds/ ./output/backgrounds/
COPY --from=asciinema-stage /build/attack-chain-demo.svg ./output/
COPY --from=qrcode-stage /build/qr-slides.png /build/qr-pdf.png /build/qr-pptx.png ./output/qr/
RUN marp slides.md --html --allow-local-files -o output/slides.html
RUN marp slides.md --html --allow-local-files --pdf -o output/slides.pdf
RUN marp slides.md --html --allow-local-files --pptx -o output/slides.pptx
RUN cp title-bg.svg output/

# Final: serve via HTTP (file:// can't load relative assets)
# slides.html refs use output/ prefix (output/images/*, output/backgrounds/*),
# so assets must live under output/ in the web root.
FROM nginx:alpine
COPY --from=marp-stage /build/output/ /usr/share/nginx/html/output/
COPY --from=marp-stage /build/output/slides.html /usr/share/nginx/html/index.html
COPY --from=marp-stage /build/output/title-bg.svg /usr/share/nginx/html/
EXPOSE 80
CMD ["sh", "-c", "cp -r /usr/share/nginx/html/output/* /output/ 2>/dev/null; exec nginx -g 'daemon off;'"]
