# DM Fog Migration Plan: CPU to GPU

This document outlines the step-by-step plan to migrate DM fog operations from CPU pixel logic to GPU-based workflows in the Omni-Crawl codebase.

## 1. Audit Fog Operations
- Identify all methods/functions in FogSystem.gd, FogOverlay.gd, and DM tools that manipulate fog using Image, pixel, or CPU logic (e.g., set_pixel, fill, resize, save_png_to_buffer).

## 2. Separate DM and Player Logic
- Refactor fog logic to clearly separate DM (GPU) and Player (CPU) modes.
- In DM mode, disable or bypass all pixel-based fog manipulation.

## 3. Centralize GPU Fog State
- Ensure FogSystem.gd is the sole authority for fog state in DM mode.
- Store fog state as a GPU texture (from SubViewport or shader output), not as an Image.

## 4. Update Reveal/Hide/History Methods
- Replace pixel-editing methods with GPU-based operations:
  - Use shader parameters, viewport updates, or texture swaps to reveal/hide fog.
  - Trigger GPU-side history updates by swapping textures or updating shader inputs.

## 5. Integrate GPU Fog with UI
- Update FogOverlay.gd and DM UI tools to render fog using the GPU texture from FogSystem.gd.
- Pass the GPU fog texture to FogOverlay.gd for drawing.

## 6. Remove CPU Pixel Logic
- Delete or disable all Image/pixel manipulation code for DM mode.
- Ensure all fog changes in DM mode are performed via GPU pipeline.

## 7. Test and Validate
- Test DM fog reveal, hide, and history operations to ensure they work via GPU logic.
- Validate that Player mode still works with CPU mask logic.

## 8. Document and Clean Up
- Document the new GPU-based workflow for DM fog.
- Remove obsolete pixel-based code and update comments.

---

Follow this plan to ensure DM fog operations are fully migrated to GPU logic, improving performance and visual fidelity.