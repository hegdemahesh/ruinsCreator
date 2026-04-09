# Substance Painter LLOD Batch Plugin

This folder is an external Substance 3D Painter plugin bundle prepared for batch texturing of LLOD FBX assets.

## Folder Structure

The bundle matches Painter's external plugin layout:

```text
substance_painter_llod_batch_plugin/
  plugins/
    llod_batch_textures/
      __init__.py
  modules/
    llod_batch_core.py
  startup/
    README.txt
```

## What It Does

The plugin scans tagged LLOD FBX files, creates a Painter project for each low-poly mesh, tries to find a matching HLOD mesh for baking, sets resolution from the file name, applies a same-named smart material, and exports textures to a per-asset output folder.

Expected low-poly file naming:

```text
assetname_greyrock_2k.fbx
assetname_LLOD_oldwood_4k.fbx
```

Expected high-poly file naming:

```text
assetname.fbx
```

## Configuration

Edit these constants in [modules/llod_batch_core.py](modules/llod_batch_core.py):

1. `LOW_POLY_FOLDER`
2. `HIGH_POLY_FOLDER`
3. `EXPORT_FOLDER`
4. `SMART_MATERIAL_CONTEXT` if you want to restrict smart-material search to a specific shelf context
5. `EXPORT_PRESET_CONTEXT`
6. `EXPORT_PRESET_NAME`

The current default export preset is configured as:

```text
PBR Metallic Roughness_copy_copy
```

If your copied Painter export preset has a slightly different name, update `EXPORT_PRESET_NAME` to match it exactly.

Your smart materials in Painter should match the material tag names exactly:

1. `greyrock`
2. `blackrock`
3. `oldwood`
4. `oldbroze`
5. `mixed`

## Install In Painter

### Option 1: External plugin path

Set the environment variable `SUBSTANCE_PAINTER_PLUGINS_PATH` to this folder:

```text
d:\github\ruinsCreator\scripts\substance_painter_llod_batch_plugin
```

Then launch Substance 3D Painter.

### Option 2: Copy into Painter documents folder

Copy the `plugins/llod_batch_textures` folder into:

```text
C:\Users\<your-user>\Documents\Adobe\Adobe Substance 3D Painter\python\plugins\
```

If you use this method, also make sure the `modules` folder is available on Painter's Python path. The clean way is still Option 1.

## Run The Plugin

1. Open Substance 3D Painter.
2. Enable the Python plugin if Painter asks for it.
3. Open the dock panel named `LLOD Batch Textures`.
4. Click `Run Batch`.

The plugin also adds a File menu action named `Batch Texture LLOD Assets`.

## UI

The dock panel shows:

1. the configured low-poly, high-poly, and export folders
2. a `Run Batch` button
3. a `Clear Log` button
4. a scrolling log output area

## Important Notes

The plugin is intentionally written defensively because some Painter APIs differ across versions.

The most likely first-pass adjustment points are:

1. the exact project settings constructor used by your Painter version
2. the exact bake-settings setter for the high-poly reference mesh
3. the exact API call used to assign a smart material resource onto a fill layer

If the plugin fails, copy the log from the dock panel and use that to tighten the version-specific calls.

## Recommended First Test

Run the plugin on a single known asset first, confirm:

1. project creation works
2. the correct HLOD mesh is found
3. bake starts
4. the smart material is found
5. export completes to the expected folder
