#!/usr/bin/env python3
"""manifest.py — 설치 목록(manifests/*.manifest) 해석·점검·제거 계획 (install.sh·uninstall-backend.sh 공용)

사용: manifest.py check <manifest>                 읽기 전용 점검(파일을 쓰지 않는다)
      manifest.py uninstall <manifest>… [--apply]   기본 dry-run. --apply 때만 보관·항목 제거

환경: HOME(~ 확장), AO_REPO(리포 상대 경로의 기준), AO_TS(보관 폴더 시각 — 시험용)
종료: 0 정상 / 1 check에서 필수 항목 없음 / 12 manifest 형식 오류·알 수 없는 kind·selector
형식(계획 §2-4): 탭 구분 `kind owner path selector note`, '#' 줄은 주석.
owner: herdr(툴이 설치 — 편집 금지, 제거 때 보관만) / ours-backend / ours-core(백엔드 교체 때 보존)
       / existing(어떤 경우에도 건드리지 않음). kind allow = 잔존 허용 예외.
Python 3.9 호환(macOS /usr/bin/python3).
"""
import json
import os
import re
import shutil
import sys
import time

HOME = os.environ.get("HOME", "")
REPO = os.environ.get("AO_REPO", "")
PRESERVE = ("ours-core",)  # kind existing 도 늘 보존(owner 칸은 '-'·rex 등)
REQUIRED = ("link", "config", "hook", "setting", "adapter", "doc")
HOOK_SEL = re.compile(r'^hooks\.([A-Za-z*]+)\[command~=(.+)\]$')
TOML_SEL = re.compile(r'^([A-Za-z0-9_]+)\."(.+)"$')


class ManifestError(Exception):
    pass


def expand(path):
    if path.startswith("~/"):
        return os.path.join(HOME, path[2:])
    if path.startswith("/"):
        return path
    return os.path.join(REPO, path)


def in_repo(path):
    return not (path.startswith("~/") or path.startswith("/"))


def parse(manifest):
    if not os.path.isfile(manifest):
        raise ManifestError("manifest 없음: %s" % manifest)
    rows = []
    with open(manifest, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) != 5:
                raise ManifestError("%s:%d 칸 수 %d (5여야 함)" % (manifest, n, len(cols)))
            rows.append(dict(zip(("kind", "owner", "path", "selector", "note"), cols)))
    return rows


# ───────── selector 해석
def text_files(path):
    """파일이면 그것, 폴더면 아래의 텍스트 파일(archive 폴더·CHANGELOG 제외)"""
    if os.path.isfile(path):
        yield path
        return
    for root, dirs, files in os.walk(path):
        dirs[:] = sorted(d for d in dirs if d != "archive" and not d.startswith("."))
        for fn in sorted(files):
            if "CHANGELOG" in fn:
                continue
            yield os.path.join(root, fn)


def grep(path, pat):
    """대소문자 무시 포함 검색 → [(파일, 줄 번호, 줄)]"""
    hits = []
    if not os.path.exists(path):
        return hits
    low = pat.lower()
    for fp in text_files(path):
        try:
            with open(fp, encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    if low in line.lower():
                        hits.append((fp, n, line.rstrip("\n")))
        except (UnicodeDecodeError, OSError):
            continue
    return hits


def hook_matches(path, sel):
    """hooks.<이벤트|*>[command~=부분] → [(이벤트, 그룹 번호, 훅 번호, command)]"""
    m = HOOK_SEL.match(sel)
    if not m:
        raise ManifestError("알 수 없는 selector: %s" % sel)
    ev, sub = m.group(1), m.group(2)
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    out = []
    for e, groups in (d.get("hooks") or {}).items():
        if ev != "*" and e != ev:
            continue
        for gi, g in enumerate(groups or []):
            for hi, h in enumerate(g.get("hooks") or []):
                c = h.get("command") or ""
                if sub in c:
                    out.append((e, gi, hi, c))
    return out


def toml_table(path, sel):
    m = TOML_SEL.match(sel)
    if not m:
        raise ManifestError("알 수 없는 selector: %s" % sel)
    head = '[%s."%s"]' % (m.group(1), m.group(2))
    if not os.path.isfile(path):
        return False
    with open(path, encoding="utf-8") as f:
        return any(line.strip() == head for line in f)


def config_value(path, key):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith(key):
                return line[len(key):].strip()
    return None


def exists(path):
    return os.path.lexists(path)


def allow_rules(rows):
    return [(expand(r["path"]), r["selector"][len("grep:"):]) for r in rows
            if r["kind"] == "allow" and r["selector"].startswith("grep:")]


def rule_hits(row, allows):
    """rule 잔존 → (남은 [(파일, 줄, 내용)], 허용으로 뺀 수)"""
    if not row["selector"].startswith("grep:"):
        raise ManifestError("rule selector는 grep:<패턴>: %s" % row["selector"])
    hits = grep(expand(row["path"]), row["selector"][len("grep:"):])
    kept, skipped = [], 0
    for h in hits:
        if any((h[0] == ap or h[0].startswith(ap.rstrip("/") + "/")) and pat.lower() in h[2].lower()
               for ap, pat in allows):
            skipped += 1
        else:
            kept.append(h)
    return kept, skipped


# ───────── check (읽기 전용)
def describe(row):
    """→ (있음 여부 또는 None(정보 항목), 세부)"""
    k, p, s = row["kind"], expand(row["path"]), row["selector"]
    if k == "link":
        if os.path.islink(p):
            t = os.readlink(p)
            return True, "→ %s%s" % (t, "" if os.access(p, os.X_OK) else " (대상 실행 불가)")
        if exists(p):
            return False, "충돌: 링크가 아닌 파일이 있음"
        return False, "-"
    if k == "config":
        v = config_value(p, s)
        return (v is not None), ("%s%s" % (s, v) if v is not None else "-")
    if k in ("hook", "adapter", "doc"):
        return exists(p), "-"
    if k == "setting":
        n = len(hook_matches(p, s))
        return n > 0, "%d개" % n
    if k == "existing":
        if s == "-":
            ok = exists(p)
        elif s.startswith("hooks."):
            ok = len(hook_matches(p, s)) > 0
        else:
            ok = toml_table(p, s)
        return None, "보존 대상 %s" % ("있음" if ok else "없음")
    raise ManifestError("알 수 없는 kind: %s" % k)


def cmd_check(manifest):
    rows = parse(manifest)
    allows = allow_rules(rows)
    need = have = residue = 0
    for r in rows:
        if r["kind"] == "rule":
            kept, skipped = rule_hits(r, allows)
            residue += len(kept)
            state, detail = "잔존 %d건" % len(kept), ("허용 제외 %d건" % skipped if skipped else "-")
        elif r["kind"] == "allow":
            n = len(grep(expand(r["path"]), r["selector"][len("grep:"):]))
            state, detail = "허용 %d건" % n, r["note"]
        else:
            ok, detail = describe(r)
            if ok is None:
                state = "정보"
            else:
                need += 1
                have += 1 if ok else 0
                state = "있음" if ok else "없음"
        print("\t".join((state, r["kind"], r["owner"], r["path"], detail)))
    name = os.path.basename(manifest).rsplit(".", 1)[0]
    print("== %s: 필수 %d/%d 있음, rule 잔존 %d건(allow 제외)" % (name, have, need, residue))
    return 0 if have == need else 1


# ───────── uninstall (기본 dry-run)
def archive_root():
    ts = os.environ.get("AO_TS") or time.strftime("%Y%m%d-%H%M%S")
    return ts


def plan_row(row, allows, backend, ts):
    """→ (동작, 세부, 실행 함수 또는 None)"""
    k, owner, raw = row["kind"], row["owner"], row["path"]
    p = expand(raw)
    if k == "existing" or owner in PRESERVE: return "보존", row["note"], None  # GUARD:preserve
    if k == "allow":
        return "허용(유지)", row["note"], None
    if k == "rule":
        kept, _ = rule_hits(row, allows)
        locs = ["%s:%d" % (f, n) for f, n, _ in kept]
        return "위치만 출력 %d건" % len(kept), " ".join(locs) or "-", None
    if k in ("adapter", "doc") or in_repo(raw):
        return "git 이력 보관(수동 git rm)", row["note"], None
    dest_dir = os.path.join(HOME, ".claude", "archive", "agent-orchestrator", "%s-%s" % (backend, ts))
    rel = os.path.relpath(p, HOME) if p.startswith(HOME + "/") else p.lstrip("/")
    dest = os.path.join(dest_dir, rel)
    if k == "hook":
        if not exists(p):
            return "없음(건너뜀)", "-", None

        def mv():
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.move(p, dest)
        return "보관 예정", "→ " + dest, mv
    if k == "setting":
        hits = hook_matches(p, row["selector"])
        if not hits:
            return "없음(건너뜀)", "-", None

        def rm():
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(p, dest)  # 원본 백업 먼저
            with open(p, encoding="utf-8") as f:
                d = json.load(f)
            drop = {(e, gi, hi) for e, gi, hi, _ in hits}
            hooks = d.get("hooks") or {}
            for e in list(hooks):
                groups = []
                for gi, g in enumerate(hooks[e] or []):
                    hs = [h for hi, h in enumerate(g.get("hooks") or []) if (e, gi, hi) not in drop]
                    if g.get("hooks") and not hs:
                        continue  # 비게 된 그룹은 뺀다
                    g = dict(g)
                    g["hooks"] = hs
                    groups.append(g)
                if groups:
                    hooks[e] = groups
                else:
                    del hooks[e]
            tmp = p + ".ao-tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(d, f, ensure_ascii=False, indent=2)
                f.write("\n")
            os.replace(tmp, p)
        return "항목 제거 예정 %d개(원본 백업 후)" % len(hits), "백업 → " + dest, rm
    raise ManifestError("알 수 없는 kind: %s (%s)" % (k, raw))


def cmd_uninstall(manifests, apply, backend):
    ts = archive_root()
    plans = []
    for m in manifests:
        rows = parse(m)
        allows = allow_rules(rows)
        for r in rows:
            act, detail, fn = plan_row(r, allows, backend, ts)
            plans.append((r, act, detail, fn))
    for r, act, detail, _ in plans:  # 계획 전체를 먼저 출력(실행 전 실패 없음 확인)
        print("\t".join((act, r["kind"], r["owner"], r["path"], detail)))
    todo = [x for x in plans if x[3]]
    if not apply:
        print("== dry-run: 실행할 동작 %d개, 파일 변경 없음 (--apply 로 실행)" % len(todo))
        return 0
    for r, act, _, fn in todo:
        fn()
        print("완료\t%s\t%s" % (r["kind"], r["path"]))
    print("== apply: %d개 실행" % len(todo))
    return 0


def main(argv):
    try:
        if len(argv) == 2 and argv[0] == "check":
            return cmd_check(argv[1])
        if len(argv) >= 3 and argv[0] == "uninstall":
            apply = "--apply" in argv
            rest = [a for a in argv[1:] if a != "--apply"]
            return cmd_uninstall(rest[1:], apply, rest[0])
        print("사용: manifest.py check <manifest> | uninstall <backend> <manifest>… [--apply]", file=sys.stderr)
        return 2
    except (ManifestError, json.JSONDecodeError) as e:
        print("manifest: %s" % e, file=sys.stderr)
        return 12


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
