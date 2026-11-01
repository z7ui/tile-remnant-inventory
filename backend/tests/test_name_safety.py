"""项目名与 CSV 导出的输入安全。

覆盖三类问题：
  1. 控制字符（NUL、换行、ESC）—— 会撑断日志行、破坏 JSON/CSV 结构
  2. 不可见格式字符（零宽空格、RTL 覆写、BOM）—— 肉眼不可见，能造出"看着一样"的重名
  3. CSV 公式注入 —— Excel/WPS 会把 = + - @ 开头的单元格当公式执行
"""

from __future__ import annotations

import pytest

from app.services.movements import _csv_safe
from tests.conftest import device_headers


def _create(client, device, name):
    return client.post(
        "/api/projects",
        json={"name": name, "default_unit": "mm"},
        headers=device_headers(device["device_id"], device["device_secret"]),
    )


@pytest.mark.parametrize(
    "name",
    [
        "工地\x00项目",      # NUL：SQLite 能存，但 JSON/驱动层常被截断
        "工地\n项目",        # 换行：伪造日志行
        "工地\r项目",        # 回车：CSV/日志都受影响
        "工地\x1b[31m项目",  # ESC：终端颜色注入
        "工地\u200b项目",    # 零宽空格：不可见重名
        "工地\u202e项目",    # RTL 覆写：界面倒序显示
        "工地\ufeff项目",    # BOM
    ],
)
def test_control_and_invisible_chars_are_rejected(client, device, name):
    response = _create(client, device, name)
    assert response.status_code == 422, response.text
    assert "控制字符" in response.text or "不可见" in response.text


def test_normal_chinese_name_is_accepted(client, device):
    response = _create(client, device, "金域蓝湾 3 栋 1802")
    assert response.status_code == 201, response.text


def test_rename_goes_through_the_same_check(client, device, project):
    """改名不能成为绕过字符检查的后门。"""
    response = client.patch(
        f"/api/projects/{project['id']}",
        json={"name": "工地\u200b改名"},
        headers=project["headers"],
    )
    assert response.status_code == 422, response.text


@pytest.mark.parametrize(
    "raw,expected",
    [
        ('=HYPERLINK("http://evil","点我")', '\'=HYPERLINK("http://evil","点我")'),
        ("+1234", "'+1234"),
        ("@SUM(A1)", "'@SUM(A1)"),
        ("=cmd|'/C calc'!A0", "'=cmd|'/C calc'!A0"),
        ("-cmd", "'-cmd"),
        # 负数不能被误伤
        ("-5", "-5"),
        ("-5.25", "-5.25"),
        ("正常备注", "正常备注"),
        ("", ""),
        (None, None),
    ],
)
def test_csv_formula_injection_is_neutralised(raw, expected):
    assert _csv_safe(raw) == expected


def test_name_available_does_not_leak_conflict_project(client, project):
    """名字预检不能回传对方的 id / name / created_at。

    这个接口注册一个设备就能调（注册本身是公开的，不需要邀请码）。
    项目名往往就是工地门牌，回传等于告诉陌生人「某工地/某住户正在用」。
    """
    # conftest 的 project fixture 固定用这个名称
    conflict_name = "金域蓝湾 3 栋 1802"
    response = client.get(
        "/api/projects/name-available",
        params={"name": conflict_name},
        headers=device_headers(
            project["device"]["device_id"], project["device"]["device_secret"]
        ),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["available"] is False
    assert "conflict_project" not in body


def test_create_duplicate_does_not_leak_other_project(client, project):
    """创建重名时只说「已占用」，不回传对方项目信息。"""
    conflict_name = "金域蓝湾 3 栋 1802"
    response = client.post(
        "/api/projects",
        json={"name": conflict_name, "default_unit": "mm"},
        headers=device_headers(
            project["device"]["device_id"], project["device"]["device_secret"]
        ),
    )
    assert response.status_code == 409, response.text
    details = response.json()["error"].get("details") or {}
    assert "conflict_project_id" not in details
    assert "conflict_project_name" not in details
