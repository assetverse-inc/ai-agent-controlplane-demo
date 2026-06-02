#!/usr/bin/env python3
"""Capture proof screenshots: the companion (all scenarios run) + the ContextForge Admin UI."""
import os
from playwright.sync_api import sync_playwright

OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "screenshots")
os.makedirs(OUT, exist_ok=True)

with sync_playwright() as p:
    b = p.chromium.launch()

    # 1) Companion with every scenario run
    pg = b.new_page(viewport={"width": 1680, "height": 1050})
    pg.goto("http://localhost:7070/", wait_until="networkidle")
    pg.wait_for_timeout(1500)
    pg.click("text=Run all scenarios")
    pg.wait_for_timeout(16000)  # let all 6 scenarios resolve against the gateway
    pg.screenshot(path=os.path.join(OUT, "companion.png"), full_page=True)
    print("saved companion.png")

    # 2) ContextForge Admin UI (login then dashboard)
    ap = b.new_page(viewport={"width": 1680, "height": 1050})
    try:
        ap.goto("http://localhost:4444/admin/login", wait_until="networkidle")
        ap.wait_for_timeout(1000)
        for sel in ["input[type=email]", "input[name=email]", "#email", "input[name=username]"]:
            if ap.query_selector(sel):
                ap.fill(sel, "admin@finbyte.demo"); break
        for sel in ["input[type=password]", "input[name=password]", "#password"]:
            if ap.query_selector(sel):
                ap.fill(sel, "changeme"); break
        for sel in ["button[type=submit]", "button:has-text('Login')", "button:has-text('Sign')", "input[type=submit]"]:
            if ap.query_selector(sel):
                ap.click(sel); break
        ap.wait_for_timeout(3500)
    except Exception as e:
        print("admin login note:", str(e)[:120])
    ap.screenshot(path=os.path.join(OUT, "admin.png"), full_page=True)
    print("saved admin.png  (url:", ap.url, ")")

    b.close()
