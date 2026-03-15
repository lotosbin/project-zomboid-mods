#!/usr/bin/env python3
"""
从网页获取 Project Zomboid 翻译格式信息的脚本
使用 Playwright 抓取 pzwiki.net 的 Translation 页面
"""

from playwright.sync_api import sync_playwright


def fetch_translation_page():
    """获取 pzwiki Translation 页面内容"""
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        )
        page = context.new_page()

        try:
            page.goto('https://pzwiki.net/wiki/Translation', timeout=90000)
            print("页面加载成功:", page.title())

            # 等待 Cloudflare 通过
            page.wait_for_timeout(10000)

            title = page.title()
            if "Just a moment" not in title:
                main_content = page.locator('#mw-content-text').inner_text()
                print("=== 页面内容 ===")
                print(main_content)
            else:
                print("检测到 Cloudflare 挑战，尝试点击按钮...")
                page.wait_for_selector('#cf-challenge-button', timeout=10000)
                page.click('#cf-challenge-button')
                page.wait_for_timeout(5000)
                main_content = page.locator('#mw-content-text').inner_text()
                print("=== 页面内容 ===")
                print(main_content)

        except Exception as e:
            print(f"错误: {e}")
            # 尝试截图
            try:
                page.screenshot(path='/tmp/pzwiki_error.png')
                print("截图已保存到 /tmp/pzwiki_error.png")
            except:
                pass

        browser.close()


if __name__ == '__main__':
    fetch_translation_page()
