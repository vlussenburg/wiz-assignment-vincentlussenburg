# Presentation Slides

Multi-stage Docker build that generates architecture diagrams, flowcharts, AI backgrounds, an animated terminal demo, and renders everything into HTML/PDF/PPTX via Marp.

## Prerequisites

- Docker
- `.env` file with `IDEOGRAM_API_KEY=<key>` (for AI-generated slide backgrounds)

## Build

```bash
cd slides
docker build --secret id=env,src=.env -t wiz-slides .
```

## Run

```bash
docker run --rm -d --name wiz-slides -p 8080:80 -v $(pwd)/output:/output wiz-slides
```

Open **http://localhost:8080** to view the slides. Built artifacts (HTML, PDF, PPTX) are also copied to `output/`.

## Live development

For iterating on `slides.md` without rebuilding:

```bash
docker run --rm -d --name wiz-slides-dev \
  -v $(pwd):/home/marp/app \
  -p 8080:8080 \
  marpteam/marp-cli --html --allow-local-files --server --listen 0.0.0.0 .
```

This watches for changes and auto-reloads. Note: generated images (diagrams, backgrounds) must already exist in `output/` from a prior build.

## Build stages

| Stage | Tool | Output |
|-------|------|--------|
| `diagrams-stage` | Python `diagrams` + Graphviz | `architecture.png` |
| `mermaid-stage` | Mermaid CLI + Chromium | `pipeline.png`, `attack-chain.png` |
| `asciinema-stage` | svg-term-cli | `attack-chain-demo.svg` |
| `backgrounds-stage` | Ideogram API | 14 slide background PNGs |
| `marp-stage` | Marp CLI + Chromium | `slides.html`, `slides.pdf`, `slides.pptx` |
