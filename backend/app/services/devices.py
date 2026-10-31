"""Device registration and heartbeat."""

from __future__ import annotations

from sqlalchemy.orm import Session

from ..errors import ApiError
from ..models import Device
from ..schemas import DeviceHeartbeatIn, DeviceRegisterIn
from ..security import hash_device_secret, new_device_secret
from ..utils import iso, new_id, utcnow
from . import audit


def register(db: Session, payload: DeviceRegisterIn, ip: str = "") -> dict:
    secret = new_device_secret()
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
    return {
        "device_id": device.id,
        "device_secret": secret,
        "name": device.name,
        "created_at": iso(device.created_at),
        "notice": "设备密钥只返回一次，请保存在系统安全存储中；丢失后需重新注册（已加入的项目需重新扫码）。",
    }


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
