#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# EAS Alert Screen — Fullscreen black display, estilo EAS real, en español
# Lee el mensaje desde ~/eas-monitor/current_alert_msg.txt
# ─────────────────────────────────────────────────────────────────────────────
import tkinter as tk
import os
import sys

MSG_FILE = os.path.expanduser("~/eas-monitor/current_alert_msg.txt")
FONT = "Courier New"

# ── Helpers ──────────────────────────────────────────────────────────────────

def word_wrap(text, max_chars=52):
    """Split text into lines of at most max_chars characters."""
    words = text.split()
    lines, current = [], []
    for word in words:
        if len(" ".join(current + [word])) > max_chars:
            if current:
                lines.append(" ".join(current))
            current = [word]
        else:
            current.append(word)
    if current:
        lines.append(" ".join(current))
    return lines


def typewriter(root, widget, text, index=0, delay=45):
    """Animate text appearing character by character."""
    if index <= len(text):
        widget.config(text=text[:index])
        root.after(delay, typewriter, root, widget, text, index + 1, delay)


# ── Main screen ───────────────────────────────────────────────────────────────

def run(message=""):
    root = tk.Tk()
    root.title("EAS ALERT")
    root.configure(bg="black")
    root.attributes("-fullscreen", True)
    root.attributes("-topmost", True)
    root.lift()
    root.focus_force()

    # Close on Escape or any key
    root.bind("<Key>", lambda e: root.destroy())
    root.bind("<Button-1>", lambda e: root.destroy())

    # ── Outer frame, vertically centered ─────────────────────────────────────
    outer = tk.Frame(root, bg="black")
    outer.place(relx=0.5, rely=0.5, anchor="center")

    def add(text, size, pady=6, animate=False, delay=45):
        lbl = tk.Label(
            outer,
            text="" if animate else text,
            fg="white",
            bg="black",
            font=(FONT, size),
            pady=pady,
            justify="center",
        )
        lbl.pack()
        if animate:
            root.after(200, typewriter, root, lbl, text, 0, delay)
        return lbl

    # ── Header — typewriter animado ───────────────────────────────────────────
    add("EMERGENCY ALERT SYSTEM", 36, pady=10, animate=True, delay=40)

    tk.Frame(outer, bg="white", height=2, width=600).pack(pady=14)

    add("THE FOLLOWING MESSAGE IS TRANSMITTED", 18, animate=True, delay=25)
    add("AT THE REQUEST OF", 18, animate=True, delay=25)
    add("", 8)
    add("THE FEDERAL EMERGENCY", 28, pady=6, animate=True, delay=35)
    add("MANAGEMENT AGENCY", 28, pady=4, animate=True, delay=35)
    add("", 8)
    add("EMERGENCY ACTION NOTIFICATION", 22, pady=6, animate=True, delay=30)

    # ── Mensaje personalizado (si hay uno) ────────────────────────────────────
    if message:
        tk.Frame(outer, bg="white", height=2, width=600).pack(pady=18)
        for line in word_wrap(message, max_chars=54):
            add(line, 17, pady=3, animate=True, delay=18)

    root.mainloop()


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    message = ""
    if os.path.exists(MSG_FILE):
        with open(MSG_FILE, "r") as f:
            message = f.read().strip()
    elif len(sys.argv) > 1:
        message = " ".join(sys.argv[1:])
    run(message)
