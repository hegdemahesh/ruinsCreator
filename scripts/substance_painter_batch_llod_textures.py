import os
import re
import time
from dataclasses import dataclass
from typing import List, Optional

import substance_painter as sp
import substance_painter.export
import substance_painter.project
import substance_painter.resource
import substance_painter.textureset

try:
    import substance_painter.baking
except ImportError:
    pass

try:
    import substance_painter.layerstack
except ImportError:
    pass

IS_QT5 = sp.application.version_info() < (10, 1, 0)

if IS_QT5:
    from PySide2 import QtGui
    from PySide2 import QtWidgets
else:
    from PySide6 import QtGui
    from PySide6 import QtWidgets


LOW_POLY_FOLDER = "D:\\shared\\3dModels\\AImodels06"
HIGH_POLY_FOLDER = "D:\\shared\\3dModels\\AImodels04"
EXPORT_FOLDER = "D:\\shared\\3dModels\\PainterExports"

SMART_MATERIAL_CONTEXT = ""
EXPORT_PRESET_CONTEXT = "starter_assets"
EXPORT_PRESET_NAME = "PBR Metallic Roughness"

KNOWN_MATERIAL_TAGS = ("greyrock", "blackrock", "oldwood", "oldbroze", "mixed")
SIZE_TO_RESOLUTION = {
    "512": 512,
    "1k": 1024,
    "2k": 2048,
    "4k": 4096,
    "8k": 8192,
}

FILENAME_PATTERN = re.compile(
    r"^(?P<asset>.+?)(?:_LLOD)?_(?P<material>greyrock|blackrock|oldwood|oldbroze|mixed)_(?P<size>512|1k|2k|4k|8k)$",
    re.IGNORECASE,
)

PLUGIN_WIDGETS = []


@dataclass
class JobSpec:
    low_poly_path: str
    high_poly_path: Optional[str]
    asset_name: str
    material_tag: str
    size_tag: str
    resolution: int
    export_folder: str

    @property
    def export_stem(self) -> str:
        return f"{self.asset_name}_{self.material_tag}_{self.size_tag}"

    @property
    def texture_export_folder(self) -> str:
        return os.path.join(self.export_folder, self.export_stem)


def log(message: str) -> None:
    print(f"[PainterBatch] {message}")


def ensure_directory(path: str) -> str:
    os.makedirs(path, exist_ok=True)
    return path


def normalize_size_tag(size_tag: str) -> str:
    return size_tag.lower()


def parse_job_from_file(file_path: str) -> Optional[JobSpec]:
    file_name = os.path.splitext(os.path.basename(file_path))[0]
    match = FILENAME_PATTERN.match(file_name)
    if not match:
        log(f"Skipping unrecognized file name: {file_name}")
        return None

    asset_name = match.group("asset")
    material_tag = match.group("material").lower()
    size_tag = normalize_size_tag(match.group("size"))
    resolution = SIZE_TO_RESOLUTION[size_tag]

    high_poly_path = find_matching_high_poly(asset_name)

    return JobSpec(
        low_poly_path=file_path,
        high_poly_path=high_poly_path,
        asset_name=asset_name,
        material_tag=material_tag,
        size_tag=size_tag,
        resolution=resolution,
        export_folder=ensure_directory(EXPORT_FOLDER),
    )


def find_matching_high_poly(asset_name: str) -> Optional[str]:
    direct_match = os.path.join(HIGH_POLY_FOLDER, f"{asset_name}.fbx")
    if os.path.exists(direct_match):
        return direct_match

    candidate_names = [
        asset_name.replace("_LLOD", ""),
        re.sub(r"_LLOD$", "", asset_name, flags=re.IGNORECASE),
    ]

    for candidate in candidate_names:
        candidate_path = os.path.join(HIGH_POLY_FOLDER, f"{candidate}.fbx")
        if os.path.exists(candidate_path):
            return candidate_path

    return None


def list_jobs(low_poly_folder: str) -> List[JobSpec]:
    jobs: List[JobSpec] = []
    for entry in sorted(os.listdir(low_poly_folder)):
        if not entry.lower().endswith(".fbx"):
            continue
        job = parse_job_from_file(os.path.join(low_poly_folder, entry))
        if job is not None:
            jobs.append(job)
    return jobs


def close_current_project() -> None:
    if not sp.project.is_open():
        return
    close_fn = getattr(sp.project, "close", None)
    if close_fn is None:
        raise RuntimeError("Painter project is already open and the API does not expose project.close().")
    close_fn()
    wait_until_project_idle("close current project")


def wait_until_project_idle(label: str, timeout_seconds: float = 120.0) -> None:
    start_time = time.time()
    while hasattr(sp.project, "is_busy") and sp.project.is_busy():
        process_ui_events()
        if time.time() - start_time > timeout_seconds:
            raise TimeoutError(f"Timed out waiting for Painter to finish: {label}")
        time.sleep(0.1)


def process_ui_events() -> None:
    application = QtWidgets.QApplication.instance()
    if application is not None:
        application.processEvents()


def create_project_for_job(job: JobSpec) -> None:
    close_current_project()

    settings = build_project_settings(job.low_poly_path)
    log(f"Creating project from {job.low_poly_path}")
    sp.project.create(settings)
    wait_until_project_idle("create project")


def build_project_settings(mesh_path: str):
    settings_class = getattr(sp.project, "Settings", None)
    if settings_class is None:
        raise RuntimeError("substance_painter.project.Settings is not available in this Painter version.")

    attempts = [
        lambda: settings_class(),
        lambda: settings_class(mesh_path),
    ]

    last_error = None
    for attempt in attempts:
        try:
            settings = attempt()
            break
        except Exception as exc:
            last_error = exc
            settings = None
    else:
        raise RuntimeError(f"Could not construct project settings: {last_error}")

    for attribute_name in ("mesh_path", "mesh_file_path", "meshFilePath", "import_mesh_path"):
        if hasattr(settings, attribute_name):
            setattr(settings, attribute_name, mesh_path)
            break

    if hasattr(sp.project, "ProjectWorkflow") and hasattr(settings, "workflow"):
        try:
            settings.workflow = sp.project.ProjectWorkflow.UV_TILE
        except Exception:
            pass

    return settings


def set_project_resolution(resolution: int) -> None:
    log(f"Setting project resolution to {resolution}x{resolution}")

    for texture_set in sp.textureset.all_texture_sets():
        resolution_set = False

        if hasattr(texture_set, "all_uv_tiles"):
            try:
                for uv_tile in texture_set.all_uv_tiles():
                    if hasattr(uv_tile, "set_resolution"):
                        uv_tile.set_resolution(resolution, resolution)
                        resolution_set = True
            except Exception:
                pass

        if not resolution_set and hasattr(texture_set, "set_resolution"):
            try:
                texture_set.set_resolution(resolution, resolution)
                resolution_set = True
            except Exception:
                pass

        if not resolution_set:
            for stack in texture_set.all_stacks():
                material = stack.material()
                if hasattr(material, "set_resolution"):
                    try:
                        material.set_resolution(resolution, resolution)
                        resolution_set = True
                        break
                    except Exception:
                        pass

        if not resolution_set:
            log(f"WARNING: Could not set resolution for texture set {texture_set.name()}")


def bake_mesh_maps(job: JobSpec) -> None:
    baking_module = getattr(sp, "baking", None)
    if baking_module is None:
        log("WARNING: substance_painter.baking is not available; skipping bake.")
        return

    configure_bake_settings(job)

    bake_fn = getattr(baking_module, "bake_selected_textures_async", None)
    if bake_fn is None:
        bake_fn = getattr(baking_module, "bake_async", None)

    if bake_fn is None:
        log("WARNING: No baking function available in this Painter version; skipping bake.")
        return

    log("Starting mesh map bake")
    bake_fn()
    wait_until_project_idle("bake mesh maps", timeout_seconds=600.0)


def configure_bake_settings(job: JobSpec) -> None:
    if job.high_poly_path is None:
        log(f"WARNING: No matching HLOD mesh found for {job.asset_name}; bake will use low poly only.")
        return

    baking_module = getattr(sp, "baking", None)
    if baking_module is None:
        return

    settings_object = None
    for class_name in ("Settings", "BakingSettings", "Parameters"):
        settings_class = getattr(baking_module, class_name, None)
        if settings_class is None:
            continue
        try:
            settings_object = settings_class()
            break
        except Exception:
            continue

    if settings_object is None:
        log("WARNING: Could not construct bake settings object; using current Painter bake settings.")
        return

    for attribute_name in (
        "high_definition_meshes",
        "highpoly_mesh_path",
        "high_poly_mesh_path",
        "secondary_mesh_path",
        "reference_mesh_path",
    ):
        if hasattr(settings_object, attribute_name):
            current_value = getattr(settings_object, attribute_name)
            if isinstance(current_value, list):
                setattr(settings_object, attribute_name, [job.high_poly_path])
            else:
                setattr(settings_object, attribute_name, job.high_poly_path)
            break

    for attribute_name in ("output_size", "resolution", "size"):
        if hasattr(settings_object, attribute_name):
            try:
                setattr(settings_object, attribute_name, job.resolution)
            except Exception:
                pass

    apply_settings_fn = getattr(baking_module, "set_common_baking_parameters", None)
    if apply_settings_fn is not None:
        try:
            apply_settings_fn(settings_object)
            log(f"Configured bake settings with HLOD mesh: {job.high_poly_path}")
            return
        except Exception as exc:
            log(f"WARNING: Could not push bake settings through set_common_baking_parameters: {exc}")

    log("WARNING: Bake settings object was created but no setter API was found; using current Painter bake settings.")


def find_smart_material_resource(material_tag: str):
    query_names = [material_tag, material_tag.lower(), material_tag.capitalize()]
    seen_urls = set()

    for query_name in query_names:
        try:
            resources = sp.resource.search(query_name)
        except Exception:
            resources = []

        for resource in resources:
            try:
                identifier = resource.identifier()
                url = identifier.url()
            except Exception:
                continue

            if url in seen_urls:
                continue
            seen_urls.add(url)

            resource_name = ""
            resource_type = None
            resource_context = ""

            try:
                resource_name = resource.gui_name().lower()
            except Exception:
                pass

            try:
                resource_type = resource.type()
            except Exception:
                pass

            try:
                resource_context = identifier.context.lower()
            except Exception:
                pass

            if resource_name != material_tag.lower():
                continue

            if SMART_MATERIAL_CONTEXT and SMART_MATERIAL_CONTEXT.lower() not in resource_context:
                continue

            if resource_type is not None and "material" not in str(resource_type).lower():
                continue

            return resource

    return None


def apply_smart_material_to_project(material_tag: str) -> None:
    resource = find_smart_material_resource(material_tag)
    if resource is None:
        raise RuntimeError(f"Could not find a smart material resource named '{material_tag}' in Painter resources.")

    resource_url = resource.identifier().url()
    log(f"Applying smart material resource {resource_url}")

    layerstack_module = getattr(sp, "layerstack", None)
    if layerstack_module is None:
        raise RuntimeError("substance_painter.layerstack is not available in this Painter version.")

    with layerstack_module.ScopedModification(f"Apply {material_tag} smart material"):
        for texture_set in sp.textureset.all_texture_sets():
            for stack in texture_set.all_stacks():
                fill_layer = create_fill_layer(stack)
                if fill_layer is None:
                    raise RuntimeError(f"Could not create a fill layer for stack {stack}")
                if not assign_resource_to_layer(fill_layer, resource):
                    raise RuntimeError(
                        "Painter API could not assign the smart material resource to the fill layer. "
                        "The job planning, resource lookup, baking, and export are ready, but this step may need a small "
                        "Painter-version-specific adjustment after the first in-app test."
                    )


def create_fill_layer(stack):
    layerstack_module = sp.layerstack

    for owner in (layerstack_module, stack):
        for function_name in (
            "create_fill_layer",
            "insert_fill_layer",
            "add_fill_layer",
            "new_fill_layer",
        ):
            function = getattr(owner, function_name, None)
            if function is None:
                continue
            try:
                return function(stack) if owner is layerstack_module else function()
            except TypeError:
                try:
                    return function()
                except Exception:
                    continue
            except Exception:
                continue

    return None


def assign_resource_to_layer(fill_layer, resource) -> bool:
    for method_name in (
        "set_material_source",
        "set_source",
        "set_resource",
    ):
        method = getattr(fill_layer, method_name, None)
        if method is None:
            continue
        try:
            method(resource)
            return True
        except Exception:
            continue

    update_function = getattr(sp.resource, "update_layer_stack_resource", None)
    if update_function is not None:
        try:
            update_function(fill_layer, resource)
            return True
        except Exception:
            pass

    return False


def build_export_preset_url() -> str:
    return sp.resource.ResourceID(
        context=EXPORT_PRESET_CONTEXT,
        name=EXPORT_PRESET_NAME,
    ).url()


def export_textures(job: JobSpec) -> None:
    ensure_directory(job.texture_export_folder)
    export_preset_url = build_export_preset_url()

    export_list = []
    for texture_set in sp.textureset.all_texture_sets():
        for stack in texture_set.all_stacks():
            export_list.append({"rootPath": str(stack)})

    config = {
        "exportShaderParams": False,
        "exportPath": job.texture_export_folder,
        "exportList": export_list,
        "exportPresets": [{"name": "default", "maps": []}],
        "defaultExportPreset": export_preset_url,
        "exportParameters": [
            {
                "parameters": {
                    "paddingAlgorithm": "infinite",
                    "sizeLog2": resolution_to_log2(job.resolution),
                    "fileName": job.export_stem,
                }
            }
        ],
    }

    log(f"Exporting textures to {job.texture_export_folder}")
    sp.export.export_project_textures(config)


def resolution_to_log2(resolution: int) -> int:
    return {
        256: 8,
        512: 9,
        1024: 10,
        2048: 11,
        4096: 12,
        8192: 13,
    }[resolution]


def run_batch() -> None:
    if not os.path.isdir(LOW_POLY_FOLDER):
        raise RuntimeError(f"Low poly folder does not exist: {LOW_POLY_FOLDER}")
    if not os.path.isdir(HIGH_POLY_FOLDER):
        log(f"WARNING: High poly folder does not exist: {HIGH_POLY_FOLDER}")

    jobs = list_jobs(LOW_POLY_FOLDER)
    if not jobs:
        log("No valid LLOD FBX files were found.")
        return

    log(f"Found {len(jobs)} Painter jobs.")

    for job in jobs:
        log(f"Starting job: {job.export_stem}")
        try:
            create_project_for_job(job)
            set_project_resolution(job.resolution)
            bake_mesh_maps(job)
            apply_smart_material_to_project(job.material_tag)
            export_textures(job)
            log(f"Completed job: {job.export_stem}")
        except Exception as exc:
            log(f"ERROR: Job failed for {job.export_stem}: {exc}")


def start_plugin() -> None:
    action_builder = QtWidgets.QAction if IS_QT5 else QtGui.QAction
    action = action_builder("Batch Texture LLOD Assets", triggered=run_batch)
    sp.ui.add_action(sp.ui.ApplicationMenu.File, action)
    PLUGIN_WIDGETS.append(action)
    log("Batch texture plugin loaded.")


def close_plugin() -> None:
    for widget in PLUGIN_WIDGETS:
        sp.ui.delete_ui_element(widget)
    PLUGIN_WIDGETS.clear()


if __name__ == "__main__":
    start_plugin()