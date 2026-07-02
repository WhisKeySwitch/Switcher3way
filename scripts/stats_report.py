#!/usr/bin/env python3
"""Ежедневный дайджест статистики RuSwitcher → Telegram.
Читает публичные счётчики GitHub (download_count релизов, звёзды), считает дельту
за сутки по истории stats/history.jsonl и шлёт отчёт в Telegram. Без телеметрии в
приложении — только агрегатные публичные числа GitHub. Зависимостей нет (urllib)."""
import json, os, urllib.request, urllib.parse, datetime

REPO = "rashn/RuSwitcher"
GH_TOKEN = os.environ.get("GITHUB_TOKEN", "")
TG_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TG_CHAT = os.environ.get("TELEGRAM_CHAT_ID", "")
HIST = "stats/history.jsonl"


def gh(path):
    req = urllib.request.Request(
        f"https://api.github.com/{path}",
        headers={
            "Authorization": f"Bearer {GH_TOKEN}" if GH_TOKEN else "",
            "Accept": "application/vnd.github+json",
            "User-Agent": "ruswitcher-stats",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def main():
    repo = gh(f"repos/{REPO}")
    releases = gh(f"repos/{REPO}/releases?per_page=100")

    per, total = {}, 0
    for rel in releases:
        dl = sum(a["download_count"] for a in rel.get("assets", []) if a["name"].endswith(".dmg"))
        per[rel["tag_name"]] = dl
        total += dl
    stars = repo["stargazers_count"]

    # МСК-дата для метки
    today = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=3)).date().isoformat()
    snap = {"date": today, "total": total, "stars": stars, "per": per}

    prev = None
    if os.path.exists(HIST):
        lines = [l for l in open(HIST, encoding="utf-8") if l.strip()]
        if lines:
            prev = json.loads(lines[-1])

    def d(cur, key, sub=None):
        if prev is None:
            return ""
        p = prev.get("per", {}).get(sub) if sub else prev.get(key)
        if p is None:
            return ""
        diff = cur - p
        return f" (+{diff})" if diff > 0 else (f" ({diff})" if diff < 0 else "")

    # свежий релиз = первый в списке (API отдаёт новыми вперёд)
    latest = releases[0]["tag_name"] if releases else None
    changed = [t for t, v in per.items() if prev and (v - prev.get("per", {}).get(t, v)) != 0]

    lines = [f"📊 RuSwitcher — {today}", ""]
    lines.append(f"Всего скачано: {total}{d(total, 'total')}")
    lines.append(f"⭐ Stars: {stars}{d(stars, 'stars')}")
    if latest:
        lines.append(f"Свежий {latest}: {per.get(latest, 0)}{d(per.get(latest, 0), None, latest)}")
    if changed:
        lines.append("")
        lines.append("Изменения за сутки:")
        for t in changed:
            lines.append(f"• {t}: {per[t]}{d(per[t], None, t)}")
    elif prev is not None:
        lines.append("")
        lines.append("За сутки без изменений по релизам.")
    report = "\n".join(lines)
    print(report)

    os.makedirs("stats", exist_ok=True)
    with open(HIST, "a", encoding="utf-8") as f:
        f.write(json.dumps(snap, ensure_ascii=False) + "\n")

    if TG_TOKEN and TG_CHAT:
        data = urllib.parse.urlencode({"chat_id": TG_CHAT, "text": report}).encode()
        req = urllib.request.Request(f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage", data=data)
        with urllib.request.urlopen(req, timeout=30) as r:
            print("telegram sent:", r.status)
    else:
        print("Telegram secrets not set — report printed only (add TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID).")


if __name__ == "__main__":
    main()
