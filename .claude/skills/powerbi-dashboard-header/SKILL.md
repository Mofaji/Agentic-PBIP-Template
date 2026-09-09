---
name: powerbi-dashboard-header
description: 'Standardizes the header band and page chrome across dashboard pages - canvas background template, logo/divider/title/slicer/action-button layout, visual title styling, and the left-gap and top-gap adjustments that follow from moving filters into the header. Use when building or restyling a dashboard page header, aligning pages to the reference page, repositioning filters into the top navigation, or applying consistent visual titles and backgrounds across a report.'
---

# Dashboard Page Design Standardization Guide

This document outlines the standard frontend design requirements for all dashboard pages based on the "final boss" reference page (`07f2c11fecd49dd91c92`). 

## Repository Final Boss Alignment

`copilot-instructions.md` is the final authority. This guide describes a client reference layout and **conflicts with it in one place**: section 3 below turns visual container titles on, while `copilot-instructions.md` rule 10 forbids them because titles are drawn on the SVG canvas background.

Resolve it per project, explicitly:

- **SVG-canvas projects (this template's default):** rule 10 wins - no visual container titles, no visual background. Use this file for the header band only (sections 1 and 2).
- **Projects that follow the reference page:** apply section 3 as written, and record the exception in the project's spec under `specs/`.

Never mix the two on one page.

## 1. Canvas Background
All pages must use the standard background template.
- **Image File**: `default_template.svg`
- **Location**: `RegisteredResources`
- **Configuration** (in `page.json`):
  - `image.name`: `'default_template.svg'`
  - `image.url.ResourcePackageItem`: `PackageName: "RegisteredResources", PackageType: 1, ItemName: "default_template22254715379846457.svg"`
  - `scaling`: `'Normal'`
  - `transparency`: `0D`

## 2. Header Layout (Top Navigation)
The header must remain exactly the same across all pages. The following components should be present in order from left to right:

1. **Logo**
   - **Source Visual**: `3b5c0bef5f209909ea98`
   - **Type**: `image`
2. **Vertical Divider**
   - **Source Visual**: `d849ba136233006d0c03`
   - **Type**: `shape`
3. **Page Title**
   - **Coordinates**: `x: 175.8`, `y: 10.8`, `width: 450`, `height: 43.02`
   - **Style**: Font family `Segoe UI`, Font size `16pt`, Color `White` (#FFFFFF), Background Color `None`.
   - **Positioning**: Needs to align next to the vertical divider.
4. **Filters / Slicers**
   - **Reference Design**: Take design inspiration from the slicer `c56b951563bc44d79aab`.
   - **Action**: Existing page filters should be repositioned to the right side of the header area and have their theme/styling updated to match the reference.
5. **Action Buttons (Top Right)**
   - **Source Visuals**: `eed863193986bc4a6f6b` (Back Button) followed by `742256cef03587b3b8b4` (Home Button).
   - **Type**: `actionButton`

## 3. Visual Titles
All standard charts/visuals on the page must have a consistent title styling applied:
- **Reference Style**: Follow the title styling found in `visualContainerObjects` of `2d33dd7cb9413f3e47d1`.
  - **Font**: `Segoe UI Semibold`
  - **Size**: `9D`
  - **Bold**: `true`
  - **Show**: `true`
- **Content**: Generate a 1-sentence AI-based descriptive title for each visual based on the columns and values being displayed in that specific visual.
- **Background**: For all visuals that are located below the header section (i.e. the main content area charts/tables), ensure they have a general background color of `#FFFFFF` (White) applied.
- **Fill Left Space**: Since the old filters are moved to the header, there will be blank space on the left side of the page. Stretch the left-most visuals (decrease `x`, increase `width`) to fill this gap.
- **Top Gap**: For the first row of visuals directly below the header, increase their `y` coordinate by `12` and reduce their `height` by `12` to create a slight gap between the header and the visuals.
