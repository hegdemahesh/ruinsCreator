import argparse
import sys
from pathlib import Path

import bpy


DEFAULT_INPUT_FOLDER = Path(r"D:\shared\3dModels\groups")
DEFAULT_OUTPUT_FOLDER = Path(r"D:\shared\3dModels\groups_glb")


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    else:
        argv = []

    parser = argparse.ArgumentParser(
        description="Import FBX files into Blender and export them as GLB files with embedded textures."
    )
    parser.add_argument(
        "input_folder",
        nargs="?",
        default=str(DEFAULT_INPUT_FOLDER),
        help="Folder containing FBX files.",
    )
    parser.add_argument(
        "output_folder",
        nargs="?",
        default=str(DEFAULT_OUTPUT_FOLDER),
        help="Folder where GLB files will be written.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing GLB files in the output folder.",
    )
    return parser.parse_args(argv)


def log(message: str) -> None:
    print(f"[FBX2GLB] {message}")


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    for collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.textures,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.armatures,
        bpy.data.actions,
    ):
        orphans = [block for block in collection if block.users == 0]
        for block in orphans:
            collection.remove(block)


def ensure_object_mode() -> None:
    active_object = bpy.context.view_layer.objects.active
    if active_object is not None and active_object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def import_fbx(file_path: Path) -> None:
    bpy.ops.import_scene.fbx(filepath=str(file_path), use_image_search=True)


def export_glb(file_path: Path) -> None:
    bpy.ops.export_scene.gltf(
        filepath=str(file_path),
        export_format="GLB",
        export_image_format="AUTO",
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_apply=False,
        use_selection=False,
    )


def convert_file(fbx_path: Path, output_folder: Path, overwrite: bool) -> bool:
    glb_path = output_folder / f"{fbx_path.stem}.glb"

    if glb_path.exists() and not overwrite:
        log(f"Skipping existing file: {glb_path.name}")
        return False

    clear_scene()
    ensure_object_mode()

    log(f"Importing {fbx_path.name}")
    import_fbx(fbx_path)

    log(f"Exporting {glb_path.name}")
    export_glb(glb_path)
    return True


def main() -> int:
    args = parse_args()
    input_folder = Path(args.input_folder)
    output_folder = Path(args.output_folder)

    if not input_folder.exists() or not input_folder.is_dir():
        log(f"Input folder does not exist: {input_folder}")
        return 1

    output_folder.mkdir(parents=True, exist_ok=True)
    fbx_files = sorted(input_folder.glob("*.fbx"))

    if not fbx_files:
        log(f"No FBX files found in {input_folder}")
        return 1

    exported_count = 0
    skipped_count = 0
    failed_count = 0

    for fbx_path in fbx_files:
        try:
            if convert_file(fbx_path, output_folder, overwrite=args.overwrite):
                exported_count += 1
            else:
                skipped_count += 1
        except Exception as exc:  # Blender reports operator failures through Python exceptions.
            failed_count += 1
            log(f"ERROR processing {fbx_path.name}: {exc}")

    clear_scene()
    log(
        "Summary: "
        f"exported={exported_count}, skipped={skipped_count}, failed={failed_count}, output={output_folder}"
    )
    return 0 if failed_count == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())