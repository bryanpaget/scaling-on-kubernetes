# Makefile for generating Marp PDF presentations and Typst reports

# Variables
HEADER_MD_EN = config/header-en.md
HEADER_MD_FR = config/header-fr.md
TEMP_DIR = temp
IMG_DIR = img
MARP_OPTS = --allow-local-files --pdf-outlines

# English presentation
INPUT_MD_EN = content/slides-en.md
COMBINED_MD_EN = $(TEMP_DIR)/slides-en-combined.md
OUTPUT_PDF_EN = vpa-presentation-en.pdf

# French presentation
INPUT_MD_FR = content/slides-fr.md
COMBINED_MD_FR = $(TEMP_DIR)/slides-fr-combined.md
OUTPUT_PDF_FR = vpa-presentation-fr.pdf

# English report (Typst)
REPORT_TYP_EN = report/report-en.typ
REPORT_OUTPUT_EN = vpa-report-en.pdf

# French report (Typst)
REPORT_TYP_FR = report/report-fr.typ
REPORT_OUTPUT_FR = vpa-report-fr.pdf

# GitHub Pages site
SITE_DIR = docs
LANDING_PAGE = config/landing.html

# Default target
all: pdf reports

# Create both PDFs and reports
pdf: setup combine-en combine-fr
	@echo "Building English presentation PDF..."
	npx marp $(MARP_OPTS) --pdf --output $(OUTPUT_PDF_EN) $(COMBINED_MD_EN)
	@echo "Building French presentation PDF..."
	npx marp $(MARP_OPTS) --pdf --output $(OUTPUT_PDF_FR) $(COMBINED_MD_FR)
	@echo "Presentation PDFs built: $(OUTPUT_PDF_EN), $(OUTPUT_PDF_FR)"

# Create both reports using Typst
reports:
	@echo "Building English report PDF (Typst)..."
	typst compile $(REPORT_TYP_EN) $(REPORT_OUTPUT_EN)
	@echo "Building French report PDF (Typst)..."
	typst compile $(REPORT_TYP_FR) $(REPORT_OUTPUT_FR)
	@echo "Report PDFs built: $(REPORT_OUTPUT_EN), $(REPORT_OUTPUT_FR)"

# Build English only
pdf-en: setup combine-en
	@echo "Building English presentation PDF..."
	npx marp $(MARP_OPTS) --pdf --output $(OUTPUT_PDF_EN) $(COMBINED_MD_EN)
	@echo "PDF built: $(OUTPUT_PDF_EN)"

# Build French only
pdf-fr: setup combine-fr
	@echo "Building French presentation PDF..."
	npx marp $(MARP_OPTS) --pdf --output $(OUTPUT_PDF_FR) $(COMBINED_MD_FR)
	@echo "PDF built: $(OUTPUT_PDF_FR)"

# Build English report only
report-en:
	@echo "Building English report PDF (Typst)..."
	typst compile $(REPORT_TYP_EN) $(REPORT_OUTPUT_EN)
	@echo "Report built: $(REPORT_OUTPUT_EN)"

# Build both presentations and landing page as HTML for GitHub Pages
html: setup combine-en combine-fr
	@echo "Building HTML presentations into $(SITE_DIR)/ for GitHub Pages..."
	mkdir -p $(SITE_DIR)
	npx marp --html --allow-local-files --output $(SITE_DIR)/en.html $(COMBINED_MD_EN)
	npx marp --html --allow-local-files --output $(SITE_DIR)/fr.html $(COMBINED_MD_FR)
	cp $(LANDING_PAGE) $(SITE_DIR)/index.html
	@mkdir -p $(SITE_DIR)/img
	@cp -r $(IMG_DIR)/* $(SITE_DIR)/img/ 2>/dev/null || true
	@touch $(SITE_DIR)/.nojekyll
	@echo "Site built in $(SITE_DIR)/: index.html, en.html, fr.html, img/"

# Build French report only
report-fr:
	@echo "Building French report PDF (Typst)..."
	typst compile $(REPORT_TYP_FR) $(REPORT_OUTPUT_FR)
	@echo "Report built: $(REPORT_OUTPUT_FR)"

# Setup temporary directory and copy assets
setup:
	@echo "Setting up temporary directory..."
	mkdir -p $(TEMP_DIR)
	@cp -r $(IMG_DIR)/* $(TEMP_DIR)/img/ 2>/dev/null || mkdir -p $(TEMP_DIR)/img && cp -r $(IMG_DIR)/* $(TEMP_DIR)/img/ 2>/dev/null || true

# Combine header and English content
combine-en: setup
	@echo "Combining header and English content..."
	cat $(HEADER_MD_EN) $(INPUT_MD_EN) > $(COMBINED_MD_EN)

# Combine header and French content
combine-fr: setup
	@echo "Combining header and French content..."
	cat $(HEADER_MD_FR) $(INPUT_MD_FR) > $(COMBINED_MD_FR)

# Clean up generated files
clean:
	@echo "Cleaning up..."
	rm -rf $(TEMP_DIR)
	rm -f $(OUTPUT_PDF_EN) $(OUTPUT_PDF_FR)
	rm -f $(REPORT_OUTPUT_EN) $(REPORT_OUTPUT_FR)

# Install Marp CLI and Chromium
deps:
	@echo "Installing Marp CLI and Chromium..."
	npm install -g @marp-team/marp-cli
	sudo apt-get update && sudo apt-get install -y chromium --no-install-recommends

# Install Chromium only (if Marp already installed)
install-chromium:
	@echo "Installing Chromium..."
	sudo apt-get update && sudo apt-get install -y chromium --no-install-recommends

# Check if Marp is installed
check-marp:
	@which marp || (echo "Marp CLI not installed. Run 'make deps' first." && exit 1)

# Preview the English presentation in browser
preview-en: setup combine-en check-marp
	@echo "Starting preview server for English presentation..."
	marp $(COMBINED_MD_EN) --server --allow-local-files --port 8080

# Preview the French presentation in browser
preview-fr: setup combine-fr check-marp
	@echo "Starting preview server for French presentation..."
	marp $(COMBINED_MD_FR) --server --allow-local-files --port 8081

# Build and open PDFs
open: pdf
	@if command -v xdg-open > /dev/null; then \
		xdg-open $(OUTPUT_PDF_EN); \
		xdg-open $(OUTPUT_PDF_FR); \
	elif command -v open > /dev/null; then \
		open $(OUTPUT_PDF_EN); \
		open $(OUTPUT_PDF_FR); \
	else \
		echo "Cannot open PDFs automatically. Please open $(OUTPUT_PDF_EN) and $(OUTPUT_PDF_FR) manually."; \
	fi

# Help target
help:
	@echo "Available targets:"
	@echo "  all            - Build both PDFs and reports (default)"
	@echo "  pdf            - Build both presentation PDFs"
	@echo "  reports        - Build both report PDFs"
	@echo "  html           - Build both presentations as HTML into docs/ (GitHub Pages)"
	@echo "  pdf-en         - Build English presentation PDF only"
	@echo "  pdf-fr         - Build French presentation PDF only"
	@echo "  report-en      - Build English report PDF only"
	@echo "  report-fr      - Build French report PDF only"
	@echo "  preview-en     - Start live preview server for English (port 8080)"
	@echo "  preview-fr     - Start live preview server for French (port 8081)"
	@echo "  open           - Build PDFs and open them"
	@echo "  deps           - Install Marp CLI and Chromium"
	@echo "  install-chromium - Install Chromium only"
	@echo "  clean          - Remove generated files"
	@echo "  help           - Show this help message"

.PHONY: all pdf pdf-en pdf-fr reports report-en report-fr html setup combine-en combine-fr clean deps install-chromium preview-en preview-fr open help check-marp
