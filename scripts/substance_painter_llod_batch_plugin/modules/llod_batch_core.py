import os
import re
import inspect
import json
import time
from dataclasses import dataclass
from typing import Callable, List, Optional

import substance_painter as sp
import substance_painter.export
import substance_painter.project
import substance_painter.resource
import substance_painter.textureset

try:
    import substance_painter.application
except ImportError:
    pass

try:
    import substance_painter.baking
except ImportError:
    pass

try:
    import substance_painter.layerstack
except ImportError:
    pass

try:
    import substance_painter.properties
except ImportError:
    pass


LOW_POLY_FOLDER = "D:\\shared\\3dModels\\AImodels06"
HIGH_POLY_FOLDER = "D:\\shared\\3dModels\\AImodels04"
EXPORT_FOLDER = "D:\\shared\\3dModels\\PainterExports"

SMART_MATERIAL_CONTEXT = ""
EXPORT_PRESET_CONTEXT = ""
EXPORT_PRESET_NAME = "PBR Metallic Roughness_copy"
PLUGIN_VERSION = "2026-04-09.12"
ENABLE_JS_BAKE_TRIGGER = False

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


class BatchLogger:
    def __init__(self, sink: Optional[Callable[[str], None]] = None):
        self._sink = sink

    def log(self, message: str) -> None:
        line = f"[PainterBatch] {message}"
        print(line)
        if self._sink is not None:
            self._sink(line)


class UnsupportedPainterFeatureError(RuntimeError):
    pass


class LlodBatchRunner:
    def __init__(
        self,
        low_poly_folder: str = LOW_POLY_FOLDER,
        high_poly_folder: str = HIGH_POLY_FOLDER,
        export_folder: str = EXPORT_FOLDER,
        logger: Optional[BatchLogger] = None,
    ):
        self.low_poly_folder = low_poly_folder
        self.high_poly_folder = high_poly_folder
        self.export_folder = export_folder
        self.logger = logger or BatchLogger()
        self._baking_runtime_logged = False

    def run_batch(self) -> None:
        self.log_painter_runtime()

        if not os.path.isdir(self.low_poly_folder):
            raise RuntimeError(f"Low poly folder does not exist: {self.low_poly_folder}")
        if not os.path.isdir(self.high_poly_folder):
            self.logger.log(f"WARNING: High poly folder does not exist: {self.high_poly_folder}")

        jobs = self.list_jobs(self.low_poly_folder)
        if not jobs:
            self.logger.log("No valid LLOD FBX files were found.")
            return

        self.logger.log(f"Found {len(jobs)} Painter jobs.")

        for job in jobs:
            self.logger.log(f"Starting job: {job.export_stem}")
            try:
                self.create_project_for_job(job)
                self.set_project_resolution(job.resolution)
                self.bake_mesh_maps(job)
                smart_material_applied = False
                try:
                    smart_material_applied = self.apply_smart_material_to_project(job.material_tag)
                except UnsupportedPainterFeatureError as exc:
                    self.logger.log(f"WARNING: {exc}")
                self.export_textures(job)
                if smart_material_applied:
                    self.logger.log(f"Completed job: {job.export_stem}")
                else:
                    self.logger.log(f"Completed job without smart material assignment: {job.export_stem}")
            except Exception as exc:
                self.logger.log(f"ERROR: Job failed for {job.export_stem}: {exc}")

    def log_painter_runtime(self) -> None:
        application_module = getattr(sp, "application", None)
        painter_version = "unknown"

        if application_module is not None:
            version_function = getattr(application_module, "version", None)
            if callable(version_function):
                try:
                    painter_version = str(version_function())
                except Exception:
                    painter_version = "unknown"

        self.logger.log(
            "Painter runtime: version={0}, has_layerstack={1}, has_list_layer_stack_resources={2}, has_update_layer_stack_resource={3}, has_js={4}".format(
                painter_version,
                hasattr(sp, "layerstack"),
                hasattr(sp.resource, "list_layer_stack_resources"),
                hasattr(sp.resource, "update_layer_stack_resource"),
                hasattr(sp, "js"),
            )
        )

    def list_jobs(self, low_poly_folder: str) -> List[JobSpec]:
        jobs: List[JobSpec] = []
        for entry in sorted(os.listdir(low_poly_folder)):
            if not entry.lower().endswith(".fbx"):
                continue
            job = self.parse_job_from_file(os.path.join(low_poly_folder, entry))
            if job is not None:
                jobs.append(job)
        return jobs

    def parse_job_from_file(self, file_path: str) -> Optional[JobSpec]:
        file_name = os.path.splitext(os.path.basename(file_path))[0]
        match = FILENAME_PATTERN.match(file_name)
        if not match:
            self.logger.log(f"Skipping unrecognized file name: {file_name}")
            return None

        asset_name = match.group("asset")
        material_tag = match.group("material").lower()
        size_tag = match.group("size").lower()
        resolution = SIZE_TO_RESOLUTION[size_tag]
        high_poly_asset_name = self.derive_high_poly_asset_name(file_name, asset_name)
        high_poly_path = self.find_matching_high_poly(high_poly_asset_name)

        return JobSpec(
            low_poly_path=file_path,
            high_poly_path=high_poly_path,
            asset_name=asset_name,
            material_tag=material_tag,
            size_tag=size_tag,
            resolution=resolution,
            export_folder=self.ensure_directory(self.export_folder),
        )

    def derive_high_poly_asset_name(self, low_poly_file_name: str, fallback_asset_name: str) -> str:
        suffix_patterns = (
            r"_LLOD_(greyrock|blackrock|oldwood|oldbroze|mixed)_(512|1k|2k|4k|8k)$",
            r"_LLOD_(512|1k|2k|4k|8k)$",
            r"_LLOD$",
        )

        for suffix_pattern in suffix_patterns:
            stripped_name = re.sub(suffix_pattern, "", low_poly_file_name, flags=re.IGNORECASE)
            if stripped_name != low_poly_file_name:
                return stripped_name

        return fallback_asset_name

    def find_matching_high_poly(self, asset_name: str) -> Optional[str]:
        direct_match = os.path.join(self.high_poly_folder, f"{asset_name}.fbx")
        if os.path.exists(direct_match):
            return direct_match

        candidate_names = [
            asset_name.replace("_LLOD", ""),
            re.sub(r"_LLOD$", "", asset_name, flags=re.IGNORECASE),
        ]

        for candidate in candidate_names:
            candidate_path = os.path.join(self.high_poly_folder, f"{candidate}.fbx")
            if os.path.exists(candidate_path):
                return candidate_path

        return None

    def ensure_directory(self, path: str) -> str:
        os.makedirs(path, exist_ok=True)
        return path

    def close_current_project(self) -> None:
        if not sp.project.is_open():
            return
        close_fn = getattr(sp.project, "close", None)
        if close_fn is None:
            raise RuntimeError("Painter project is already open and the API does not expose project.close().")
        close_fn()
        self.wait_until_project_idle("close current project")

    def wait_until_project_idle(self, label: str, timeout_seconds: float = 120.0) -> None:
        if not hasattr(sp.project, "is_busy"):
            return

        try:
            if not sp.project.is_busy():
                return
        except Exception:
            return

        qt_core = self._qt_core()
        application = self._qt_application()

        if qt_core is None or application is None:
            start_time = time.time()
            while sp.project.is_busy():
                self.process_ui_events()
                if time.time() - start_time > timeout_seconds:
                    raise TimeoutError(f"Timed out waiting for Painter to finish: {label}")
                time.sleep(0.05)
            return

        self.logger.log(f"Waiting for Painter to finish: {label}")

        event_loop = qt_core.QEventLoop()
        poll_timer = qt_core.QTimer()
        poll_timer.setInterval(50)

        timeout_timer = qt_core.QTimer()
        timeout_timer.setSingleShot(True)

        state = {"timed_out": False}

        def on_poll() -> None:
            try:
                if not sp.project.is_busy():
                    event_loop.exit(0)
            except Exception:
                event_loop.exit(0)

        def on_timeout() -> None:
            state["timed_out"] = True
            event_loop.exit(1)

        poll_timer.timeout.connect(on_poll)
        timeout_timer.timeout.connect(on_timeout)

        poll_timer.start()
        timeout_timer.start(int(timeout_seconds * 1000))

        exec_method = getattr(event_loop, "exec", None)
        if exec_method is None:
            exec_method = getattr(event_loop, "exec_", None)
        if exec_method is None:
            raise RuntimeError("Qt event loop does not expose exec/exec_ in this Painter runtime.")

        try:
            exec_method()
        finally:
            poll_timer.stop()
            timeout_timer.stop()

        if state["timed_out"]:
            raise TimeoutError(f"Timed out waiting for Painter to finish: {label}")

    def process_ui_events(self) -> None:
        application = self._qt_application()
        if application is not None:
            application.processEvents()

    def _qt_application(self):
        try:
            from PySide2 import QtWidgets
            return QtWidgets.QApplication.instance()
        except Exception:
            pass

        try:
            from PySide6 import QtWidgets
            return QtWidgets.QApplication.instance()
        except Exception:
            return None

    def _qt_core(self):
        try:
            from PySide2 import QtCore
            return QtCore
        except Exception:
            pass

        try:
            from PySide6 import QtCore
            return QtCore
        except Exception:
            return None

    def create_project_for_job(self, job: JobSpec) -> None:
        self.close_current_project()
        settings = self.build_project_settings(job.low_poly_path)
        settings_dict = self.settings_to_dict(settings)
        mesh_filepath = str(job.low_poly_path)
        self.logger.log(f"Creating project from {mesh_filepath}")
        self.logger.log(
            "create args: mesh_filepath_type={0}, settings_type={1}, settings_keys={2}".format(
                type(mesh_filepath).__name__,
                type(settings).__name__,
                sorted(settings_dict.keys()),
            )
        )
        project_create = getattr(sp.project, "create", None)
        if project_create is None:
            raise RuntimeError("substance_painter.project.create is not available in this Painter version.")

        if hasattr(sp.project, "Settings") and isinstance(settings, sp.project.Settings):
            project_create(mesh_filepath, [], "", settings)
        else:
            project_create(mesh_filepath, [], "", settings_dict)
        self.wait_until_project_idle("create project")

    def build_project_settings(self, mesh_path: str):
        settings_class = getattr(sp.project, "Settings", None)
        if settings_class is None:
            return {"mesh_path": mesh_path}

        attempts = [lambda: settings_class(), lambda: settings_class(mesh_path)]
        last_error = None
        settings = None

        for attempt in attempts:
            try:
                settings = attempt()
                break
            except Exception as exc:
                last_error = exc

        if settings is None:
            raise RuntimeError(f"Could not construct project settings: {last_error}")

        for attribute_name in ("mesh_path", "mesh_file_path", "meshFilePath", "import_mesh_path"):
            if hasattr(settings, attribute_name):
                setattr(settings, attribute_name, mesh_path)
                break

        return settings

    def settings_to_dict(self, settings) -> dict:
        if isinstance(settings, dict):
            return dict(settings)

        settings_dict = {}

        for attribute_name in (
            "default_save_path",
            "normal_map_format",
            "tangent_space_mode",
            "project_workflow",
            "export_path",
            "default_texture_resolution",
            "import_cameras",
            "mesh_unit_scale",
            "usd_settings",
        ):
            if hasattr(settings, attribute_name):
                settings_dict[attribute_name] = getattr(settings, attribute_name)

        return settings_dict

    def set_project_resolution(self, resolution: int) -> None:
        self.logger.log(f"Setting project resolution to {resolution}x{resolution}")

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
                self.logger.log(f"WARNING: Could not set resolution for texture set {texture_set.name()}")

    def bake_mesh_maps(self, job: JobSpec) -> None:
        baking_module = getattr(sp, "baking", None)
        if baking_module is None:
            self.logger.log("WARNING: substance_painter.baking is not available; skipping bake.")
            return

        self.configure_bake_settings(job)

        if ENABLE_JS_BAKE_TRIGGER and self.bake_mesh_maps_via_js():
            self.wait_until_project_idle("bake mesh maps via JavaScript", timeout_seconds=600.0)
            return

        if not ENABLE_JS_BAKE_TRIGGER:
            self.logger.log(
                "Skipping JavaScript bake trigger because it can open the interactive Bake Mesh dialog in Painter 9.1.2."
            )

        bake_async_fn = getattr(baking_module, "bake_async", None)
        bake_selected_fn = getattr(baking_module, "bake_selected_textures_async", None)

        if bake_async_fn is None and bake_selected_fn is None:
            self.logger.log("WARNING: No baking function available in this Painter version; skipping bake.")
            return

        texture_sets = list(sp.textureset.all_texture_sets())
        if not texture_sets:
            self.logger.log("WARNING: No texture sets are available for baking; skipping bake.")
            return

        if callable(bake_async_fn):
            for texture_set in texture_sets:
                self.logger.log(f"Starting mesh map bake for texture set {texture_set.name()}")
                bake_async_fn(texture_set)
                self.wait_until_project_idle(
                    f"bake mesh maps for texture set {texture_set.name()}",
                    timeout_seconds=600.0,
                )
            return

        self.logger.log("Starting mesh map bake for selected texture sets")
        bake_selected_fn()
        self.wait_until_project_idle("bake mesh maps", timeout_seconds=600.0)

    def bake_mesh_maps_via_js(self) -> bool:
        if not ENABLE_JS_BAKE_TRIGGER:
            return False

        if not self.has_js_bridge():
            return False

        attempts = [
            (
                "alg.baking.bake()",
                "alg.baking.bake(); JSON.stringify({ok:true});",
            ),
            (
                "alg.baking.bake(activeTextureSet)",
                (
                    "var activeSet = (alg.texturesets && alg.texturesets.getActiveTextureSet) ? alg.texturesets.getActiveTextureSet() : null;"
                    "if (!activeSet) { JSON.stringify({ok:false, reason:'no-active-texture-set'}); }"
                    "else { alg.baking.bake(activeSet); JSON.stringify({ok:true}); }"
                ),
            ),
        ]

        for label, script in attempts:
            try:
                result = self.evaluate_js(script)
                self.logger.log(f"JS bake trigger {label}: {result}")
                if result and '"ok":true' in str(result).lower():
                    self.logger.log(f"Starting mesh map bake through JavaScript API: {label}")
                    return True
            except Exception as exc:
                self.logger.log(f"WARNING: JS bake trigger {label} failed: {exc}")

        return False

    def configure_bake_settings(self, job: JobSpec) -> None:
        if job.high_poly_path is None:
            self.logger.log(f"WARNING: No matching HLOD mesh found for {job.asset_name}; bake will use low poly only.")
            return

        baking_module = getattr(sp, "baking", None)
        if baking_module is None:
            return

        self.log_baking_runtime(baking_module)

        apply_settings_functions = self.get_bake_settings_functions(baking_module)
        if not apply_settings_functions:
            if self.configure_bake_settings_via_js(job):
                self.logger.log(f"Configured bake settings with HLOD mesh through JavaScript API: {job.high_poly_path}")
                return

            self.log_js_baking_capabilities(job.high_poly_path)
            self.logger.log(
                "WARNING: No confirmed bake-settings setter API is exposed in this Painter version; "
                "the high-definition mesh path could not be assigned automatically, so Painter will use its current bake settings."
            )
            return

        any_applied = False

        for texture_set in sp.textureset.all_texture_sets():
            for stack in texture_set.all_stacks():
                settings_object = self.build_bake_settings_object(baking_module, texture_set, stack)
                if settings_object is None:
                    continue

                high_poly_assigned = self.assign_high_poly_to_settings(settings_object, job.high_poly_path)
                resolution_assigned = self.assign_resolution_to_settings(settings_object, job.resolution)

                self.logger.log(
                    "Bake settings prepared for stack={0}: settings_type={1}, high_poly_assigned={2}, resolution_assigned={3}".format(
                        stack,
                        type(settings_object).__name__,
                        high_poly_assigned,
                        resolution_assigned,
                    )
                )

                if self.apply_bake_settings(apply_settings_functions, settings_object, texture_set, stack):
                    any_applied = True

        if any_applied:
            self.logger.log(f"Configured bake settings with HLOD mesh: {job.high_poly_path}")
            return

        fallback_dict = self.build_bake_settings_dict(job.high_poly_path, job.resolution)
        if self.apply_bake_settings(apply_settings_functions, fallback_dict, None, None):
            self.logger.log(f"Configured bake settings with HLOD mesh through dict fallback: {job.high_poly_path}")
            return

        self.logger.log(
            "WARNING: Could not push bake settings into Painter 9.1.2. The high-definition mesh is still not being set."
        )

    def log_baking_runtime(self, baking_module) -> None:
        if self._baking_runtime_logged:
            return

        self._baking_runtime_logged = True

        available_members = [name for name in dir(baking_module) if not name.startswith("_")]
        self.logger.log(f"Baking runtime members: {', '.join(sorted(available_members))}")

        for function_name in (
            "set_common_baking_parameters",
            "set_linked_group_common_parameters",
            "get_link_group_common_parameters",
            "set_linked_group",
            "get_link_group",
            "get_linked_texture_sets_common_parameters",
            "get_linked_texture_sets",
            "bake_selected_textures_async",
            "bake_async",
        ):
            function = getattr(baking_module, function_name, None)
            if function is None:
                continue
            try:
                signature = str(inspect.signature(function))
            except Exception:
                signature = "<signature unavailable>"
            self.logger.log(f"Baking function {function_name}{signature}")

        for class_name in ("Settings", "BakingSettings", "Parameters", "BakingParameters"):
            settings_class = getattr(baking_module, class_name, None)
            if settings_class is None:
                continue
            self.logger.log(f"Baking settings class available: {class_name}")

        properties_module = getattr(sp, "properties", None)
        if properties_module is not None:
            property_members = [name for name in dir(properties_module) if not name.startswith("_")]
            self.logger.log(f"Properties runtime members: {', '.join(sorted(property_members))}")

    def get_bake_settings_functions(self, baking_module):
        functions = []
        for function_name in ("set_common_baking_parameters",):
            function = getattr(baking_module, function_name, None)
            if callable(function):
                functions.append((function_name, function))
        return functions

    def build_bake_settings_object(self, baking_module, texture_set, stack):
        constructor_variants = []

        for class_name in ("Settings", "BakingSettings", "Parameters", "BakingParameters"):
            settings_class = getattr(baking_module, class_name, None)
            if settings_class is None:
                continue
            constructor_variants.extend(
                [
                    (class_name, settings_class, tuple()),
                    (class_name, settings_class, (stack,)),
                    (class_name, settings_class, (texture_set,)),
                    (class_name, settings_class, (texture_set, stack)),
                    (class_name, settings_class, (stack, texture_set)),
                ]
            )

        for class_name, settings_class, arguments in constructor_variants:
            try:
                settings_object = settings_class(*arguments)
                self.logger.log(
                    "Constructed bake settings object: class={0}, args={1}".format(
                        class_name,
                        len(arguments),
                    )
                )
                return settings_object
            except TypeError:
                continue
            except Exception as exc:
                self.logger.log(
                    "WARNING: Failed to construct bake settings class={0} args={1}: {2}".format(
                        class_name,
                        len(arguments),
                        exc,
                    )
                )

        self.logger.log(f"WARNING: Could not construct bake settings object for stack {stack}.")
        return None

    def build_bake_settings_dict(self, high_poly_path: str, resolution: int) -> dict:
        return {
            "high_definition_meshes": [high_poly_path],
            "highpoly_mesh_path": high_poly_path,
            "high_poly_mesh_path": high_poly_path,
            "secondary_mesh_path": high_poly_path,
            "reference_mesh_path": high_poly_path,
            "output_size": resolution,
            "resolution": resolution,
            "size": resolution,
        }

    def assign_high_poly_to_settings(self, settings_object, high_poly_path: str) -> bool:
        assigned = False

        for attribute_name in (
            "high_definition_meshes",
            "high_definition_mesh_paths",
            "highpoly_mesh_path",
            "high_poly_mesh_path",
            "high_poly_meshes",
            "secondary_mesh_path",
            "reference_mesh_path",
        ):
            if not hasattr(settings_object, attribute_name):
                continue
            try:
                current_value = getattr(settings_object, attribute_name)
                new_value = [high_poly_path] if isinstance(current_value, list) else high_poly_path
                setattr(settings_object, attribute_name, new_value)
                assigned = True
            except Exception as exc:
                self.logger.log(f"WARNING: Could not set bake attribute {attribute_name}: {exc}")

        nested_names = ("common_parameters", "common", "parameters")
        for nested_name in nested_names:
            nested_value = getattr(settings_object, nested_name, None)
            if nested_value is not None and nested_value is not settings_object:
                if self.assign_high_poly_to_settings(nested_value, high_poly_path):
                    assigned = True

        return assigned

    def assign_resolution_to_settings(self, settings_object, resolution: int) -> bool:
        assigned = False

        for attribute_name in ("output_size", "resolution", "size"):
            if not hasattr(settings_object, attribute_name):
                continue
            try:
                setattr(settings_object, attribute_name, resolution)
                assigned = True
            except Exception as exc:
                self.logger.log(f"WARNING: Could not set bake resolution attribute {attribute_name}: {exc}")

        nested_names = ("common_parameters", "common", "parameters")
        for nested_name in nested_names:
            nested_value = getattr(settings_object, nested_name, None)
            if nested_value is not None and nested_value is not settings_object:
                if self.assign_resolution_to_settings(nested_value, resolution):
                    assigned = True

        return assigned

    def apply_bake_settings(self, apply_settings_functions, settings_object, texture_set, stack) -> bool:
        for function_name, function in apply_settings_functions:
            call_variants = [
                (settings_object,),
            ]

            if stack is not None:
                call_variants.extend(
                    [
                        (stack, settings_object),
                        (settings_object, stack),
                    ]
                )

            if texture_set is not None:
                call_variants.extend(
                    [
                        (texture_set, settings_object),
                        (settings_object, texture_set),
                        ([texture_set], settings_object),
                        (settings_object, [texture_set]),
                    ]
                )

            if texture_set is not None and stack is not None:
                call_variants.extend(
                    [
                        (texture_set, stack, settings_object),
                        (stack, texture_set, settings_object),
                        (settings_object, texture_set, stack),
                        ([texture_set], stack, settings_object),
                    ]
                )

            for arguments in call_variants:
                try:
                    function(*arguments)
                    self.logger.log(
                        "Applied bake settings through {0} with arg_count={1}".format(
                            function_name,
                            len(arguments),
                        )
                    )
                    return True
                except TypeError:
                    continue
                except Exception as exc:
                    self.logger.log(
                        "WARNING: {0} failed with arg_count={1}: {2}".format(
                            function_name,
                            len(arguments),
                            exc,
                        )
                    )

        return False

    def log_js_baking_capabilities(self, high_poly_path: str) -> None:
        if not self.has_js_bridge():
            self.logger.log("WARNING: Painter JavaScript bridge is not available for bake diagnostics.")
            return

        probes = {
            "alg_baking_keys": "JSON.stringify((alg.baking && Object.keys(alg.baking).sort()) || [])",
            "alg_texturesets_keys": "JSON.stringify((alg.texturesets && Object.keys(alg.texturesets).sort()) || [])",
            "high_poly_path_echo": f"JSON.stringify({high_poly_path!r})",
        }

        self.logger.log(f"Probing Painter JavaScript baking API. high_poly={high_poly_path}")

        for label, script in probes.items():
            try:
                result = self.evaluate_js(script)
                self.logger.log(f"JS bake probe {label}: {result}")
            except Exception as exc:
                self.logger.log(f"WARNING: JS bake probe {label} failed: {exc}")

    def has_js_bridge(self) -> bool:
        js_module = getattr(sp, "js", None)
        evaluate = getattr(js_module, "evaluate", None) if js_module is not None else None
        return callable(evaluate)

    def evaluate_js(self, script: str):
        js_module = getattr(sp, "js", None)
        evaluate = getattr(js_module, "evaluate", None) if js_module is not None else None
        if not callable(evaluate):
            raise RuntimeError("Painter JavaScript bridge is not available.")
        return evaluate(script)

    def configure_bake_settings_via_js(self, job: JobSpec) -> bool:
        if not self.has_js_bridge():
            return False

        high_poly_json = json.dumps(job.high_poly_path)
        resolution_json = json.dumps(job.resolution)

        attempts = [
            (
                "setCommonBakingParameters(object)",
                (
                    "var params = alg.baking.commonBakingParameters();"
                    "if (params && typeof params === 'object') {"
                    "  params.highDefinitionMeshes = [" + high_poly_json + "];"
                    "  params.highDefinitionMeshPaths = [" + high_poly_json + "];"
                    "  params.highPolyMeshes = [" + high_poly_json + "];"
                    "  params.highPolyMeshPaths = [" + high_poly_json + "];"
                    "  params.outputSize = " + resolution_json + ";"
                    "  params.resolution = " + resolution_json + ";"
                    "  alg.baking.setCommonBakingParameters(params);"
                    "  JSON.stringify({ok:true, keys:Object.keys(params).sort()});"
                    "} else {"
                    "  JSON.stringify({ok:false, reason:'no-params-object'});"
                    "}"
                ),
            ),
            (
                "setTextureSetBakingParameters(object)",
                (
                    "var sets = (alg.texturesets && alg.texturesets.structure) ? alg.texturesets.structure() : [];"
                    "var firstSet = (sets && sets.length) ? sets[0] : null;"
                    "if (!firstSet) { JSON.stringify({ok:false, reason:'no-texture-set'}); }"
                    "else {"
                    "  var params = (alg.baking && alg.baking.textureSetBakingParameters) ? alg.baking.textureSetBakingParameters(firstSet) : null;"
                    "  if (params && typeof params === 'object') {"
                    "    params.highDefinitionMeshes = [" + high_poly_json + "];"
                    "    params.highDefinitionMeshPaths = [" + high_poly_json + "];"
                    "    params.highPolyMeshes = [" + high_poly_json + "];"
                    "    params.highPolyMeshPaths = [" + high_poly_json + "];"
                    "    params.outputSize = " + resolution_json + ";"
                    "    params.resolution = " + resolution_json + ";"
                    "    alg.baking.setTextureSetBakingParameters(firstSet, params);"
                    "    JSON.stringify({ok:true, keys:Object.keys(params).sort()});"
                    "  } else {"
                    "    JSON.stringify({ok:false, reason:'no-texture-set-params'});"
                    "  }"
                    "}"
                ),
            ),
        ]

        any_success = False

        for label, script in attempts:
            try:
                result = self.evaluate_js(script)
                self.logger.log(f"JS bake apply {label}: {result}")
                if result and '"ok":true' in str(result).lower():
                    any_success = True
            except Exception as exc:
                self.logger.log(f"WARNING: JS bake apply {label} failed: {exc}")

        return any_success

    def find_smart_material_resource(self, material_tag: str):
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

                try:
                    resource_name = resource.gui_name().lower()
                except Exception:
                    resource_name = ""

                if resource_name != material_tag.lower():
                    continue

                try:
                    resource_type = resource.type()
                    if resource_type is not None and "material" not in str(resource_type).lower():
                        continue
                except Exception:
                    pass

                if SMART_MATERIAL_CONTEXT:
                    try:
                        resource_context = identifier.context.lower()
                    except Exception:
                        resource_context = ""
                    if SMART_MATERIAL_CONTEXT.lower() not in resource_context:
                        continue

                return resource

        return None

    def apply_smart_material_to_project(self, material_tag: str) -> bool:
        resource = self.find_smart_material_resource(material_tag)
        if resource is None:
            raise RuntimeError(f"Could not find a smart material resource named '{material_tag}' in Painter resources.")

        resource_url = resource.identifier().url()
        self.logger.log(f"Applying smart material resource {resource_url}")

        layerstack_module = getattr(sp, "layerstack", None)
        if layerstack_module is not None:
            with layerstack_module.ScopedModification(f"Apply {material_tag} smart material"):
                for texture_set in sp.textureset.all_texture_sets():
                    for stack in texture_set.all_stacks():
                        fill_layer = self.create_fill_layer(stack)
                        if fill_layer is None:
                            raise RuntimeError(f"Could not create a fill layer for stack {stack}")
                        if not self.assign_resource_to_layer(fill_layer, resource):
                            raise RuntimeError(
                                "Painter API could not assign the smart material resource to the fill layer. "
                                "This usually means the layer assignment call differs in your Painter version."
                            )
            return True

        if self.apply_smart_material_via_resource_api(resource):
            return True

        self.log_js_material_capabilities(resource_url)

        raise UnsupportedPainterFeatureError(
            "Smart material application is not supported by the Python API exposed in this Painter version. "
            "The project was created and baked, but no compatible material-assignment API was found. "
            "Continuing without smart material assignment so textures can still be exported."
        )

    def log_js_material_capabilities(self, resource_url: str) -> None:
        if not self.has_js_bridge():
            self.logger.log("WARNING: Painter JavaScript bridge is not available for further smart material diagnostics.")
            return

        probes = {
            "alg_keys": "JSON.stringify(Object.keys(alg).sort())",
            "alg_resources_keys": "JSON.stringify((alg.resources && Object.keys(alg.resources).sort()) || [])",
            "alg_layers_keys": "JSON.stringify((alg.layers && Object.keys(alg.layers).sort()) || [])",
            "alg_mapexport_keys": "JSON.stringify((alg.mapexport && Object.keys(alg.mapexport).sort()) || [])",
            "resource_lookup": 'JSON.stringify((alg.resources && alg.resources.findResources) ? alg.resources.findResources("your_assets", "*") : [])',
        }

        self.logger.log(f"Probing Painter JavaScript API for smart material fallback. resource={resource_url}")

        for label, script in probes.items():
            try:
                result = self.evaluate_js(script)
                self.logger.log(f"JS probe {label}: {result}")
            except Exception as exc:
                self.logger.log(f"WARNING: JS probe {label} failed: {exc}")

    def apply_smart_material_via_resource_api(self, resource) -> bool:
        list_function = getattr(sp.resource, "list_layer_stack_resources", None)
        update_function = getattr(sp.resource, "update_layer_stack_resource", None)

        if list_function is None or update_function is None:
            self.logger.log(
                "WARNING: Older Painter fallback is unavailable because list/update layer-stack resource APIs are missing."
            )
            return False

        any_stack_updated = False

        for texture_set in sp.textureset.all_texture_sets():
            for stack in texture_set.all_stacks():
                stack_resources = self.list_stack_resources(list_function, stack, texture_set)
                self.logger.log(
                    "Fallback resource API: stack={0}, discovered_resources={1}".format(
                        stack,
                        len(stack_resources),
                    )
                )

                if not stack_resources:
                    continue

                for current_resource in stack_resources:
                    if not self.is_material_like_resource(current_resource):
                        continue
                    if self.try_update_stack_resource(update_function, stack, texture_set, current_resource, resource):
                        any_stack_updated = True

        if any_stack_updated:
            self.logger.log("Applied smart material through the older resource replacement API.")
            self.wait_until_project_idle("apply smart material")
            return True

        self.logger.log(
            "WARNING: Older Painter resource API was found, but no material-like stack resources could be replaced."
        )
        return False

    def list_stack_resources(self, list_function, stack, texture_set):
        variants = (
            (stack,),
            (texture_set,),
            tuple(),
        )

        for arguments in variants:
            try:
                result = list_function(*arguments)
            except TypeError:
                continue
            except Exception as exc:
                self.logger.log(f"WARNING: list_layer_stack_resources failed for args={len(arguments)}: {exc}")
                continue

            resources = self.extract_resources_from_listing(result)
            if resources:
                return resources

        return []

    def extract_resources_from_listing(self, result):
        if result is None:
            return []

        if isinstance(result, dict):
            values = []
            for item in result.values():
                if isinstance(item, (list, tuple, set)):
                    values.extend(item)
                else:
                    values.append(item)
            return [value for value in values if self.looks_like_resource(value)]

        if isinstance(result, (list, tuple, set)):
            resources = []
            for item in result:
                if self.looks_like_resource(item):
                    resources.append(item)
                elif isinstance(item, (list, tuple, set)):
                    resources.extend(value for value in item if self.looks_like_resource(value))
                elif isinstance(item, dict):
                    resources.extend(
                        value for value in item.values() if self.looks_like_resource(value)
                    )
            return resources

        if self.looks_like_resource(result):
            return [result]

        return []

    def looks_like_resource(self, value) -> bool:
        return hasattr(value, "identifier") and callable(getattr(value, "identifier"))

    def is_material_like_resource(self, resource) -> bool:
        try:
            resource_type = resource.type()
            if resource_type is not None and "material" in str(resource_type).lower():
                return True
        except Exception:
            pass

        try:
            category = resource.category()
            if category is not None and "material" in str(category).lower():
                return True
        except Exception:
            pass

        try:
            usages = resource.usages()
            if usages is not None and "material" in str(usages).lower():
                return True
        except Exception:
            pass

        return False

    def try_update_stack_resource(self, update_function, stack, texture_set, current_resource, new_resource) -> bool:
        call_variants = (
            (current_resource, new_resource),
            (stack, current_resource, new_resource),
            (texture_set, current_resource, new_resource),
            (stack, new_resource),
            (texture_set, new_resource),
        )

        for arguments in call_variants:
            try:
                update_function(*arguments)
                self.logger.log(
                    "Fallback resource update succeeded with args={0}".format(len(arguments))
                )
                return True
            except TypeError:
                continue
            except Exception as exc:
                self.logger.log(
                    "WARNING: update_layer_stack_resource failed for args={0}: {1}".format(
                        len(arguments),
                        exc,
                    )
                )

        return False

    def create_fill_layer(self, stack):
        layerstack_module = sp.layerstack

        for owner in (layerstack_module, stack):
            for function_name in ("create_fill_layer", "insert_fill_layer", "add_fill_layer", "new_fill_layer"):
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

    def assign_resource_to_layer(self, fill_layer, resource) -> bool:
        for method_name in ("set_material_source", "set_source", "set_resource"):
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

    def build_export_preset_url(self) -> str:
        candidate_names = [EXPORT_PRESET_NAME]
        if EXPORT_PRESET_NAME.lower().endswith("_copy"):
            candidate_names.append(EXPORT_PRESET_NAME[:-5])
        if "PBR Metallic Roughness" not in candidate_names:
            candidate_names.append("PBR Metallic Roughness")

        if EXPORT_PRESET_CONTEXT:
            for preset_name in candidate_names:
                return sp.resource.ResourceID(
                    context=EXPORT_PRESET_CONTEXT,
                    name=preset_name,
                ).url()

        seen_urls = set()

        for preset_name in candidate_names:
            try:
                resources = sp.resource.search(preset_name)
            except Exception as exc:
                self.logger.log(f"WARNING: Could not search export presets for '{preset_name}': {exc}")
                continue

            for resource in resources:
                try:
                    identifier = resource.identifier()
                    url = identifier.url()
                except Exception:
                    continue

                if url in seen_urls:
                    continue
                seen_urls.add(url)

                try:
                    resource_name = resource.gui_name().lower()
                except Exception:
                    resource_name = ""

                if resource_name != preset_name.lower():
                    continue

                try:
                    resource_type = resource.type()
                    if resource_type is not None and "export" not in str(resource_type).lower() and "preset" not in str(resource_type).lower():
                        continue
                except Exception:
                    pass

                self.logger.log(f"Using export preset resource {url}")
                return url

        for preset_name in candidate_names:
            if preset_name != "PBR Metallic Roughness":
                continue
            try:
                url = sp.resource.ResourceID(
                    context="starter_assets",
                    name=preset_name,
                ).url()
                self.logger.log(f"Using built-in Painter export preset {url}")
                return url
            except Exception as exc:
                self.logger.log(f"WARNING: Could not build starter_assets preset '{preset_name}': {exc}")

        current_preset = self.get_current_export_preset_via_js()
        if current_preset:
            self.logger.log(f"Using current Painter export preset {current_preset}")
            return current_preset

        raise RuntimeError(
            f"Could not find export preset '{EXPORT_PRESET_NAME}'. "
            "Set EXPORT_PRESET_NAME to the exact Painter preset name, set EXPORT_PRESET_CONTEXT explicitly, or select a project export preset in Painter before running the batch."
        )

    def get_current_export_preset_via_js(self) -> Optional[str]:
        if not self.has_js_bridge():
            return None

        try:
            result = self.evaluate_js(
                "JSON.stringify({"
                "preset:(alg.mapexport && alg.mapexport.getProjectExportPreset) ? alg.mapexport.getProjectExportPreset() : null,"
                "options:(alg.mapexport && alg.mapexport.getProjectExportOptions) ? alg.mapexport.getProjectExportOptions() : null"
                "})"
            )
            self.logger.log(f"JS export preset probe: {result}")
        except Exception as exc:
            self.logger.log(f"WARNING: JS export preset probe failed: {exc}")
            return None

        try:
            payload = json.loads(result)
        except Exception:
            return None

        preset = payload.get("preset")
        if isinstance(preset, str) and preset:
            return preset

        return None

    def export_textures(self, job: JobSpec) -> None:
        self.ensure_directory(job.texture_export_folder)
        export_preset_url = self.build_export_preset_url()

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
                        "sizeLog2": self.resolution_to_log2(job.resolution),
                        "fileName": job.export_stem,
                    }
                }
            ],
        }

        self.logger.log(f"Exporting textures to {job.texture_export_folder}")
        sp.export.export_project_textures(config)

    def resolution_to_log2(self, resolution: int) -> int:
        return {
            256: 8,
            512: 9,
            1024: 10,
            2048: 11,
            4096: 12,
            8192: 13,
        }[resolution]
