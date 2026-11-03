#!/usr/bin/env python3
"""Build a reproducible, indexed English–Chinese dictionary; no user data involved."""
import csv
import hashlib
import json
import pathlib
import re
import sqlite3
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
REV = "39cfb9672c0906b63569e0453c2e6abfb9ab182a"
BASE = f"https://raw.githubusercontent.com/skywind3000/ECDICT/{REV}/"
SOURCE = ROOT / "local-records/dictionary-source/ecdict.csv"
DEST = ROOT / "native/Resources"

def normalize(text):
    text = text.lower().replace("’", "'").replace("‘", "'").replace("–", "-").replace("—", "-")
    return " ".join(text.split()).strip(" .,!?:;\"()[]{}")

def main():
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True, exist_ok=True)
    if not SOURCE.exists():
        temporary = SOURCE.with_suffix(".download")
        urllib.request.urlretrieve(BASE + "ecdict.csv", temporary)
        temporary.replace(SOURCE)
    license_path = DEST / "ECDICT-LICENSE.txt"
    if not license_path.exists():
        urllib.request.urlretrieve(BASE + "LICENSE", license_path)
    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    lock_path = ROOT / "scripts/dictionary-source.json"
    lock = json.loads(lock_path.read_text())
    if digest != lock["sha256"]:
        raise SystemExit("Dictionary source checksum mismatch; refusing to build")
    target = DEST / "dictionary.sqlite"
    temporary = target.with_suffix(".building")
    temporary.unlink(missing_ok=True)
    db = sqlite3.connect(temporary)
    db.executescript("""
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        CREATE TABLE entries(id INTEGER PRIMARY KEY, term TEXT NOT NULL, normalized TEXT NOT NULL,
          phonetic TEXT NOT NULL, translation TEXT NOT NULL, rank INTEGER NOT NULL);
        CREATE TABLE forms(form TEXT NOT NULL, entry_id INTEGER NOT NULL,
          PRIMARY KEY(form,entry_id)) WITHOUT ROWID;
        CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
    """)
    count = 0
    with SOURCE.open(newline="", encoding="utf-8-sig") as source:
        for row in csv.DictReader(source):
            word, translation = row["word"].strip(), row["translation"].strip()
            # English definitions without a Chinese gloss cannot fulfill English → Chinese.
            if not word or not re.search(r"[\u3400-\u9fff]", translation):
                continue
            normal = normalize(word)
            if not normal or len(normal) > 160:
                continue
            rank = min([int(row[k]) for k in ("bnc", "frq") if row.get(k, "").isdigit() and int(row[k]) > 0] or [999999])
            count += 1
            db.execute("INSERT INTO entries VALUES(?,?,?,?,?,?)", (count, word, normal, row.get("phonetic", ""), translation.replace("\\n", "\n"), rank))
            for exchange in row.get("exchange", "").split("/"):
                kind, _, form = exchange.partition(":")
                if kind not in {"p", "d", "i", "3", "r", "t", "s"}:
                    continue
                for variant in form.split(","):
                    variant = normalize(variant)
                    if variant and variant != normal:
                        db.execute("INSERT OR IGNORE INTO forms VALUES(?,?)", (variant, count))
    db.executescript("CREATE INDEX entries_normalized ON entries(normalized,rank); CREATE INDEX entries_rank ON entries(rank);")
    metadata = {"source": "ECDICT", "revision": REV, "source_sha256": digest, "entries": str(count), "schema": "1"}
    db.executemany("INSERT INTO metadata VALUES(?,?)", metadata.items())
    db.commit()
    assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    db.execute("VACUUM")
    db.close()
    temporary.replace(target)
    size = target.stat().st_size
    assert size < 300_000_000, f"Dictionary exceeds 300 MB budget: {size}"
    metadata["bytes"] = size
    metadata["license"] = "MIT; see ECDICT-LICENSE.txt"
    (DEST / "dictionary-info.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    print(f"Built {count:,} entries, {size / 1_000_000:.1f} MB: {target}")

if __name__ == "__main__":
    main()
