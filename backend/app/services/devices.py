"""Device registration and heartbeat."""

from __future__ import annotations

from sqlalchemy import func
from sqlalchemy.orm import Session

from ..errors import ApiError
from ..models import Device, Project
from ..schemas import DeviceHeartbeatIn, DeviceRegisterIn
from ..security import hash_device_secret, new_device_secret
from ..utils import iso, new_id, utcnow
from . import audit

# 「第 N 位用户」的庆祝节点，前端据此放礼炮 + 弹恭喜窗。
MILESTONES: tuple[int, ...] = (10, 100, 1000, 10000, 100000)


def active_device_count(db: Session) -> int:
    """未撤销的设备数，也就是「有多少人装了」。"""
    return int(db.query(func.count(Device.id)).filter(Device.revoked_at.is_(None)).scalar() or 0)


def stats(db: Session) -> dict:
    projects = int(db.query(func.count(Project.id)).scalar() or 0)
    return {
        "devices": active_device_count(db),
        "projects": projects,
        "milestones": list(MILESTONES),
    }


def register(db: Session, payload: DeviceRegisterIn, ip: str = "") -> dict:
    secret = new_device_secret()
    # 新设备的序号 = 当前未撤销设备数 + 1。
    # 并发注册时可能有两个请求拿到同一个序号（count 与 insert 之间有窗口），
    # 但里程碑只用来放个礼炮，差一位不影响任何业务，所以不做额外加锁。
    ordinal = active_device_count(db) + 1
    device = Device(
        id=new_id(),
        name=payload.name or "施工设备",
        platform=payload.platform or "android",
        app_version=payload.app_version or "",
        secret_hash=hash_device_secret(secret),
        last_seen_at=utcnow(),
    )
    db.add(device)
    audit.log(db, "device.register", device_id=device.id, target_type="device", target_id=device.id, ip=ip)
    db.commit()
    result = {
        "device_id": device.id,
        "device_secret": secret,
        "name": device.name,
        "created_at": iso(device.created_at),
        "device_ordinal": ordinal,
        "notice": "设备密钥只返回一次，请保存在系统安全存储中；丢失后需重新注册（已加入的项目需重新扫码）。",
    }
    if ordinal in MILESTONES:
        result["milestone"] = ordinal
    return result


def heartbeat(db: Session, device: Device, payload: DeviceHeartbeatIn) -> dict:
    device.last_seen_at = utcnow()
    if payload.app_version:
        device.app_version = payload.app_version
    db.commit()
    return {"ok": True, "server_time": iso(utcnow()), "device_id": device.id}


def ensure_device_exists(db: Session, device_id: str) -> Device:
    device = db.get(Device, device_id)
    if device is None:
        raise ApiError(404, "device_not_found", "设备不存在。")
    return device
