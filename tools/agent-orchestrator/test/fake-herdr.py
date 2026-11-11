#!/usr/bin/python3
"""가짜 herdr 0.9.5 — agent-orchestrator 계약 시험용.

상태: $FAKE_DIR/state.json  {"tabs":[…], "panes":[…], "agents":[…]}
호출 기록: $FAKE_DIR/calls.log (인자를 공백으로 이어 한 줄)
강제 실패: $FAKE_DIR/fail-<그룹>-<동작> 파일이 있으면 그 내용을 오류 코드로 내고 exit 1
  (내용이 'garbage'면 해석 불가 출력, 'server-down'은 status server용)
실제 herdr처럼 오류는 stderr에 {"error":{"code":…}} 한 줄과 exit 1.
대기(--wait / agent wait)는 현재 상태가 --until 목록에 있을 때만 성공, 아니면 timeout.
"""
import json
import os
import sys

D = os.environ["FAKE_DIR"]
argv = sys.argv[1:]
with open(os.path.join(D, "calls.log"), "a") as f:
    f.write(" ".join(["herdr"] + argv) + "\n")

SP = os.path.join(D, "state.json")
st = json.load(open(SP))


def save():
    json.dump(st, open(SP, "w"), ensure_ascii=False)


def ok(obj):
    # 실제 herdr처럼 공백 없는 압축 JSON
    print(json.dumps({"id": "fake", "result": obj}, ensure_ascii=False, separators=(",", ":")))
    sys.exit(0)


def err(code):
    sys.stderr.write(json.dumps({"error": {"code": code, "message": "fake " + code}, "id": "fake"}) + "\n")
    sys.exit(1)


def opt(name, default=None):
    if name in argv:
        i = argv.index(name)
        if i + 1 < len(argv):
            return argv[i + 1]
    return default


def opts(name):
    return [argv[i + 1] for i, a in enumerate(argv[:-1]) if a == name]


g = argv[0] if argv else ""
a = argv[1] if len(argv) > 1 else ""
force = os.path.join(D, "fail-%s-%s" % (g, a))
if os.path.exists(force):
    code = open(force).read().strip()
    if code == "garbage":
        print("not json at all")
        sys.exit(0)
    err(code)


def find_agent(t):
    for x in st["agents"]:
        if x.get("name") == t or x.get("pane_id") == t:
            return x
    return None


def find_pane(p):
    for x in st["panes"]:
        if x["pane_id"] == p:
            return x
    return None


def new_pane_id():
    n = 1 + max([int(p["pane_id"].split(":p")[1]) for p in st["panes"]] + [0])
    return "w1:p%d" % n


def wait_ok(ag, untils):
    return ag.get("agent_status") in untils


if g == "status" and a == "server":
    if os.path.exists(os.path.join(D, "server-down")):
        print("status: stopped")
    else:
        print("status: running\nversion: 0.9.5")
    sys.exit(0)

if g == "agent":
    if a == "list":
        ok({"agents": st["agents"], "type": "agent_list"})
    t = argv[2] if len(argv) > 2 else ""
    if a == "start":
        if find_agent(t):
            err("agent_name_taken")
        p = find_pane(opt("--pane"))
        if not p:
            err("pane_not_found")
        if os.path.exists(os.path.join(D, "notready")):
            err("agent_not_ready")
        cli = argv[argv.index("--") + 1:] if "--" in argv else []
        ag = {"name": t, "agent": opt("--kind"), "pane_id": p["pane_id"], "agent_status": "idle",
              "cwd": p.get("cwd", "/tmp/x"), "agent_session": {"value": "uuid-" + t}, "cli": cli}
        st["agents"].append(ag)
        p["agent"] = opt("--kind")
        save()
        ok({"agent": ag, "type": "agent_info"})
    ag = find_agent(t)
    if not ag:
        err("agent_not_found")
    if a == "get":
        ok({"agent": ag, "type": "agent_info"})
    if a == "prompt":
        if ag.get("agent_status") == "blocked":
            err("agent_blocked")
        if "after_prompt" in ag:
            ag["agent_status"] = ag.pop("after_prompt")
            save()
        if "--wait" in argv and not wait_ok(ag, opts("--until")):
            err("timeout")
        ok({"ok": True})
    if a == "wait":
        if not wait_ok(ag, opts("--until")):
            err("timeout")
        ok({"agent": ag, "type": "agent_info"})
    if a == "read":
        print("screen %s line1\nscreen %s line2" % (t, t))
        sys.exit(0)
    if a == "send-keys":
        ok({"ok": True})

if g == "pane":
    if a == "list":
        ok({"panes": [p for p in st["panes"] if p["pane_id"].startswith(opt("--workspace", "") + ":")]})
    p = find_pane(argv[2] if len(argv) > 2 else opt("--pane"))
    if a == "layout":
        p = find_pane(opt("--pane"))
    if not p:
        err("pane_not_found")
    if a == "layout":
        ok({"layout": {"panes": [x for x in st["panes"] if x["tab_id"] == p["tab_id"]]}})
    if a == "get":
        ok({"pane": p})
    if a == "split":
        r = p["rect"]
        nid = new_pane_id()
        if opt("--direction") == "right":
            rect = {"x": r["x"] + 100, "y": 0, "height": 50}
        else:
            h = r["height"] // 2
            r["height"] = r["height"] - h
            rect = {"x": r["x"], "y": r["y"] + r["height"], "height": h}
        np = {"pane_id": nid, "tab_id": p["tab_id"], "rect": rect, "cwd": opt("--cwd"), "label": ""}
        st["panes"].append(np)
        save()
        ok({"pane": np})
    if a == "rename":
        p["label"] = argv[3]
        save()
        ok({"pane": p})
    if a == "read":
        print("pane %s line1\npane %s line2" % (p["pane_id"], p["pane_id"]))
        sys.exit(0)
    if a == "run":
        ok({"ok": True})
    if a == "close":
        st["panes"].remove(p)
        save()
        ok({"ok": True})

if g == "tab":
    if a == "list":
        ok({"tabs": st["tabs"], "type": "tab_list"})
    if a == "create":
        n = 1 + max([int(x["tab_id"].split(":t")[1]) for x in st["tabs"]] + [0])
        tid = "w1:t%d" % n
        tab = {"tab_id": tid, "label": opt("--label"), "workspace_id": "w1"}
        st["tabs"].append(tab)
        np = {"pane_id": new_pane_id(), "tab_id": tid, "rect": {"x": 0, "y": 0, "height": 50}, "cwd": opt("--cwd"), "label": ""}
        st["panes"].append(np)
        save()
        ok({"tab": tab, "root_pane": np, "type": "tab_created"})
    t = argv[2] if len(argv) > 2 else ""
    tab = next((x for x in st["tabs"] if x["tab_id"] == t), None)
    if not tab:
        err("tab_not_found")
    if a == "get":
        ok({"tab": tab, "type": "tab_info"})
    if a == "rename":
        tab["label"] = argv[3]
        save()
        ok({"tab": tab})

err("unknown_command")
