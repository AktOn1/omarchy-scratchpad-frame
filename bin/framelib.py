"""Shared bits of the frame designer's commands: where the state lives and the one error type that carries a plain message."""
import os

HERE = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(HERE)
STATE = os.environ.get("SCRATCHPAD_FRAME_STATE_DIR") or os.path.expanduser("~/.local/state/scratchpad-frame")


class Bad(Exception):
    pass
