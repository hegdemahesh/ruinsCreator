import os
import sys
import importlib

import substance_painter as sp

IS_QT5 = sp.application.version_info() < (10, 1, 0)

if IS_QT5:
    from PySide2 import QtCore
    from PySide2 import QtGui
    from PySide2 import QtWidgets
else:
    from PySide6 import QtCore
    from PySide6 import QtGui
    from PySide6 import QtWidgets


PLUGIN_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODULES_PATH = os.path.join(PLUGIN_ROOT, "modules")

if MODULES_PATH not in sys.path:
    sys.path.insert(0, MODULES_PATH)


def _load_core_module():
    module_name = "llod_batch_core"
    if module_name in sys.modules:
        return importlib.reload(sys.modules[module_name])
    return importlib.import_module(module_name)


CORE_MODULE = _load_core_module()
BatchLogger = CORE_MODULE.BatchLogger
EXPORT_FOLDER = CORE_MODULE.EXPORT_FOLDER
HIGH_POLY_FOLDER = CORE_MODULE.HIGH_POLY_FOLDER
LOW_POLY_FOLDER = CORE_MODULE.LOW_POLY_FOLDER
LlodBatchRunner = CORE_MODULE.LlodBatchRunner
PLUGIN_VERSION = CORE_MODULE.PLUGIN_VERSION


WIDGETS = []
LOG_PANEL = None


class LogDockWidget(QtWidgets.QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("LLOD Batch Textures")

        layout = QtWidgets.QVBoxLayout()
        self.setLayout(layout)

        config_label = QtWidgets.QLabel(
            "Low poly: {0}\nHigh poly: {1}\nExport: {2}".format(
                LOW_POLY_FOLDER,
                HIGH_POLY_FOLDER,
                EXPORT_FOLDER,
            )
        )
        config_label.setTextInteractionFlags(QtCore.Qt.TextSelectableByMouse)

        button_row = QtWidgets.QHBoxLayout()
        self.run_button = QtWidgets.QPushButton("Run Batch")
        self.clear_button = QtWidgets.QPushButton("Clear Log")
        button_row.addWidget(self.run_button)
        button_row.addWidget(self.clear_button)

        self.log_output = QtWidgets.QPlainTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setMaximumBlockCount(5000)

        layout.addWidget(config_label)
        layout.addLayout(button_row)
        layout.addWidget(self.log_output)

        self.clear_button.clicked.connect(self.log_output.clear)
        self.run_button.clicked.connect(run_batch_from_ui)

    def append_log(self, message: str) -> None:
        self.log_output.appendPlainText(message)
        scrollbar = self.log_output.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())


def append_log(message: str) -> None:
    if LOG_PANEL is not None:
        LOG_PANEL.append_log(message)


def run_batch_from_ui() -> None:
    global CORE_MODULE
    global BatchLogger
    global EXPORT_FOLDER
    global HIGH_POLY_FOLDER
    global LOW_POLY_FOLDER
    global LlodBatchRunner
    global PLUGIN_VERSION

    CORE_MODULE = _load_core_module()
    BatchLogger = CORE_MODULE.BatchLogger
    EXPORT_FOLDER = CORE_MODULE.EXPORT_FOLDER
    HIGH_POLY_FOLDER = CORE_MODULE.HIGH_POLY_FOLDER
    LOW_POLY_FOLDER = CORE_MODULE.LOW_POLY_FOLDER
    LlodBatchRunner = CORE_MODULE.LlodBatchRunner
    PLUGIN_VERSION = CORE_MODULE.PLUGIN_VERSION

    logger = BatchLogger(append_log)
    runner = LlodBatchRunner(logger=logger)
    try:
        runner.run_batch()
    except Exception as exc:
        logger.log(f"FATAL: {exc}")


def start_plugin() -> None:
    global LOG_PANEL

    action_builder = QtWidgets.QAction if IS_QT5 else QtGui.QAction
    action = action_builder("Batch Texture LLOD Assets", triggered=run_batch_from_ui)
    sp.ui.add_action(sp.ui.ApplicationMenu.File, action)
    WIDGETS.append(action)

    LOG_PANEL = LogDockWidget()
    sp.ui.add_dock_widget(LOG_PANEL, sp.ui.UIMode.Edition)
    WIDGETS.append(LOG_PANEL)

    append_log(f"[PainterBatch] Plugin loaded. version={PLUGIN_VERSION}")
    append_log(f"[PainterBatch] Plugin root: {PLUGIN_ROOT}")
    append_log(f"[PainterBatch] Module path: {MODULES_PATH}")
    append_log(f"[PainterBatch] Core module file: {getattr(CORE_MODULE, '__file__', '<unknown>')}")


def close_plugin() -> None:
    global LOG_PANEL

    for widget in WIDGETS:
        sp.ui.delete_ui_element(widget)
    WIDGETS.clear()
    LOG_PANEL = None


if __name__ == "__main__":
    start_plugin()
