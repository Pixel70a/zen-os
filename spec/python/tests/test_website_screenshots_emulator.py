import io
import os
from pathlib import Path

import pytest
from PIL import Image

from fixtures import _epub_members, _write_zip, build_library
from website_screenshots import CaptureWorkflow, ResolvedBook, load_catalog, load_profile


pytestmark = pytest.mark.skipif(
    os.environ.get("ZEN_UI_CAPTURE_INTEGRATION") != "1",
    reason="set ZEN_UI_CAPTURE_INTEGRATION=1 with a staged runtime",
)


def test_end_book_capture_finishes_hail_mary_and_selects_continue(tmp_path: Path) -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    profile = Path(__file__).parents[1] / "website_screenshot_books.example.json"
    _root, requests, _quote = load_profile(profile)
    cover = io.BytesIO()
    Image.new("RGB", (240, 360), (32, 96, 192)).save(cover, format="PNG")
    books = []
    for index, request in enumerate(requests):
        authors = "Andy Weir" if request.expected_title in (
            "Project Hail Mary: A Novel", "The Martian: A Novel",
        ) else request.authors or "Showcase Author"
        path = tmp_path / f"{index}.epub"
        members = _epub_members(request.expected_title, "", index + 1, cover.getvalue())
        members["OEBPS/content.opf"] = members["OEBPS/content.opf"].replace(
            b"<dc:creator>Zen Author</dc:creator>",
            f"<dc:creator>{authors}</dc:creator>".encode(),
        )
        _write_zip(path, members)
        books.append(ResolvedBook(
            None, request.expected_title, authors, None, path, request.role, "EPUB",
        ))
    scenario = next(scenario for scenario in load_catalog() if scenario.id == "end_book")
    run_dir = tmp_path / "artifacts"
    report = CaptureWorkflow(runtime, [scenario], books, run_dir, None).run()
    result, = report["results"]
    assert result["status"] == "passed", result
    assert result["finished_book"] == "Project Hail Mary: A Novel"
    assert result["strip_source"] == "continue"
    assert result["strip_labels"] == ["More by Andy Weir", "Series", "Continue"]
    assert result["strip_cover_count"] == 4
    assert report["source_files_unchanged"] is True
    assert report["settings_baseline_files_unchanged"] is True
    with Image.open(run_dir / "end_book.png") as image:
        assert image.size == (1272, 1696)


def test_representative_home_library_stats_reader_and_page_browser_capture(
    tmp_path: Path,
) -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    fixture = build_library(tmp_path / "fixture")
    source = fixture["epub"]
    titles = [
        "Never Split the Difference", "Flow", "Atomic Habits", "Project Hail Mary",
        "The Clean Coder", "Do Less", "The Creative Habit", "The Martian",
        "System Design", "Deep Work", "The Let Them Theory", "Wild",
    ]
    books = []
    for index, title in enumerate(titles):
        path = tmp_path / "sources" / f"{title}.epub"
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(source.read_bytes())
        role = "featured" if index == 0 else "reader" if title == "Do Less" else "library"
        books.append(ResolvedBook(index + 1, title, "Showcase Author", None, path, role, "EPUB"))
    ids = {
        "zen_home", "library_covers_full", "library_list_full", "metadata_editor",
        "stats", "quicksettings_minimal", "network_switcher", "bluetooth_switcher",
        "reader", "page_browser_grid", "page_browser_carousel",
    }
    scenarios = [scenario for scenario in load_catalog() if scenario.id in ids]
    run_dir = tmp_path / "artifacts"
    report = CaptureWorkflow(runtime, scenarios, books, run_dir, None).run()
    assert all(result["status"] == "passed" for result in report["results"]), report
    assert report["settings_baseline_files_unchanged"] is True
    for result in report["results"]:
        if result["session"] == "reader":
            assert result["reader_page"] == 10
            assert result["reader_preset"] == "(ZenOS) Chapter Time + %"
    assert {path.name for path in run_dir.glob("*.png")} == {
        f"{screen_id}.png" for screen_id in ids
    }
    assert not (run_dir / "raw").exists()
    for path in run_dir.glob("*.png"):
        with Image.open(path) as image:
            assert image.size == (1272, 1696)


def test_icon_pack_captures_use_distinct_packs_and_accents(tmp_path: Path) -> None:
    runtime = Path(os.environ["KOREADER_DIR"])
    source = build_library(tmp_path / "fixture")["epub"]
    books = [ResolvedBook(None, f"Book {index}", "Zen Author", None, source,
                          "featured" if index == 0 else "reader" if index == 1 else "library",
                          "EPUB") for index in range(12)]
    ids = {
        "icons_solar", "icons_mono", "icons_gradient", "icons_fluent",
        "launcher_solar", "launcher_mono", "launcher_gradient", "launcher_fluent",
        "navbar_underline_above", "navbar_underline_below", "navbar_filled", "navbar_outlined",
    }
    scenarios = [scenario for scenario in load_catalog() if scenario.id in ids]
    run_dir = tmp_path / "artifacts"

    report = CaptureWorkflow(runtime, scenarios, books, run_dir, None).run()

    assert {result["id"] for result in report["results"]} == ids
    assert all(result["status"] == "passed" for result in report["results"]), report
    assert len({result["icon_pack"] for result in report["results"]}) == 4
    assert len({result["accent_color"] for result in report["results"]}) == 5
    assert report["source_files_unchanged"] is True
    assert report["settings_baseline_files_unchanged"] is True
    frames = []
    for scenario in scenarios:
        with Image.open(run_dir / scenario.filename) as image:
            assert image.size == (1272, 1696)
            frames.append(image.tobytes())
            accent = scenario.options["accent_color"]
            rgb = tuple(int(accent[index:index + 2], 16) for index in (1, 3, 5))
            colors = image.convert("RGB").getcolors(image.width * image.height)
            assert any(count > 100 and color == rgb for count, color in colors)
    assert len(set(frames)) == len(scenarios)
