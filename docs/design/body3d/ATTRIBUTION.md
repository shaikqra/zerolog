# 3D body preview — source and licence

Renders built from the **Z-Anatomy** model (the artist-cleaned superficial
muscle layer), which itself derives from **BodyParts3D**.

- Z-Anatomy — *The libre 3D atlas of anatomy* — **CC BY-SA 4.0**
  https://github.com/Z-Anatomy
- BodyParts3D, © The Database Center for Life Science — **CC BY 4.0**
  (licence updated 2025-02-27; verified at
  https://dbarchive.biosciencedbc.jp/en/bodyparts3d/lic.html on 2026-11-06)

Because the cleaned meshes come from Z-Anatomy, the share-alike condition
applies to **the mesh assets**: any modified meshes we ship must remain under
CC BY-SA 4.0 with attribution. Publishing them in this public repository
satisfies that. The app's own source code is not affected — share-alike
covers the derivative *model*, not software that displays it.

Pipeline: Blender 4.2 headless (`render_preview.py` beside this file), fascia
and tendon sheets removed, muscles grouped into the app's push/pull/legs
regions, rendered with Cycles.
