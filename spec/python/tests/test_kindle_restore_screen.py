import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[3] / "modules/global/kindle_restore_screen.sh"


class KindleRestoreScreenTest(unittest.TestCase):
    def run_handoff(self, frames, refresh_fails=False):
        with tempfile.TemporaryDirectory(prefix="zen-restore-test-") as temporary:
            root = Path(temporary)
            snapshots = root / "snapshots"
            snapshots.mkdir()
            (snapshots / "screen").write_bytes(b"ZEN MESSAGE")
            (snapshots / "blank").write_bytes(b" " * 11)
            (root / "fb").write_bytes(b"ZEN MESSAGE")
            (root / "panel").write_bytes(b"ZEN MESSAGE")
            (root / "frames").write_text("\n".join(frames))
            (root / "count").write_text("0")
            scripts = {
                "usleep": '''#!/bin/sh
count=$(cat "$MOCK_ROOT/count")
count=$((count + 1))
echo "$count" > "$MOCK_ROOT/count"
frame=$(sed -n "${count}p" "$MOCK_ROOT/frames")
case "$frame" in
    white) printf '           ' > "$MOCK_ROOT/fb" ;;
    race) printf '           ' > "$MOCK_ROOT/fb"; touch "$MOCK_ROOT/race" ;;
    ui) printf 'KINDLE HOME' > "$MOCK_ROOT/fb" ;;
    startup) printf 'STARTING UP' > "$MOCK_ROOT/fb" ;;
    panel_clear) printf '           ' > "$MOCK_ROOT/panel" ;;
    short) printf ' ' > "$MOCK_ROOT/fb" ;;
    gone) rm "$MOCK_ROOT/fb" ;;
esac
''',
                "head": '''#!/bin/sh
"$MOCK_HEAD" "$@" || exit 1
if [ -f "$MOCK_ROOT/race" ]; then
    rm "$MOCK_ROOT/race"
    printf 'KINDLE HOME' > "$MOCK_ROOT/fb"
fi
''',
                "fbink": '''#!/bin/sh
printf '%s\\n' "$*" >> "$MOCK_ROOT/refreshes"
[ "$MOCK_REFRESH_EXIT" -eq 0 ] || exit "$MOCK_REFRESH_EXIT"
cp "$MOCK_ROOT/fb" "$MOCK_ROOT/panel"
''',
            }
            for name, source in scripts.items():
                (root / name).write_text(source)
                (root / name).chmod(0o755)
            result = subprocess.run(
                ["sh", str(SCRIPT), str(snapshots), "11", str(root / "fb"), str(root / "fbink")],
                env={**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                     "MOCK_ROOT": str(root), "MOCK_HEAD": shutil.which("head"),
                     "MOCK_REFRESH_EXIT": "1" if refresh_fails else "0"},
                capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(snapshots.exists(), "Temporary framebuffer copies were not removed")
            refreshes = root / "refreshes"
            return ((root / "fb").read_bytes() if (root / "fb").exists() else None,
                    refreshes.read_text().splitlines() if refreshes.exists() else [],
                    int((root / "count").read_text()),
                    (root / "panel").read_bytes(), result.stdout)

    def test_restores_cleared_screen_then_yields_to_kindle(self):
        content, refreshes, ticks, panel, log = self.run_handoff(["", "white", "white", "ui"])
        self.assertEqual(content, b"KINDLE HOME")
        self.assertGreaterEqual(len(refreshes), 2)
        self.assertEqual((panel, ticks), (b"KINDLE HOME", 11))
        self.assertIn("reason=kindle_content", log)

    def test_never_overwrites_a_returning_ui(self):
        content, _refreshes, _ticks, panel, _log = self.run_handoff(["ui"])
        self.assertEqual((content, panel), (b"KINDLE HOME", b"KINDLE HOME"))

    def test_yields_if_kindle_paints_between_read_and_restore(self):
        content, _refreshes, _ticks, panel, _log = self.run_handoff(["race"])
        self.assertEqual((content, panel), (b"KINDLE HOME", b"KINDLE HOME"))

    def test_refreshes_a_panel_clear_even_when_memory_has_not_changed(self):
        content, refreshes, ticks, panel, _log = self.run_handoff(["panel_clear"])
        self.assertEqual((content, panel, ticks), (b"ZEN MESSAGE", b"ZEN MESSAGE", 240))
        self.assertGreaterEqual(len(refreshes), 60)

    def test_survives_a_transient_startup_image_before_a_twenty_second_blank(self):
        frames = ["startup", "white"] + ["panel_clear"] * 78 + ["ui"]
        content, _refreshes, ticks, panel, _log = self.run_handoff(frames)
        self.assertEqual((content, panel, ticks), (b"KINDLE HOME", b"KINDLE HOME", 88))

    def test_stops_when_startup_takes_too_long(self):
        content, refreshes, ticks, panel, log = self.run_handoff([])
        self.assertEqual((content, panel, ticks), (b"ZEN MESSAGE", b"ZEN MESSAGE", 240))
        self.assertGreater(len(refreshes), 0)
        self.assertIn("reason=timeout", log)

    def test_stops_if_the_framebuffer_cannot_be_read_completely(self):
        for frame in ["short", "gone"]:
            with self.subTest(frame=frame):
                _content, refreshes, ticks, _panel, log = self.run_handoff([frame])
                self.assertEqual((refreshes, ticks), ([], 1))
                self.assertIn("reason=framebuffer_read", log)

    def test_stops_if_refreshing_fails(self):
        content, refreshes, ticks, _panel, log = self.run_handoff(["white", "white"], refresh_fails=True)
        self.assertEqual((content, refreshes, ticks), (b"ZEN MESSAGE", ["-q -w -W GC16 --refresh"], 1))
        self.assertIn("reason=refresh_failed", log)


if __name__ == "__main__":
    unittest.main()
