"""Device registration / heartbeat endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import client_ip, get_device
from ..models import Device
from ..ratelimit import enforce
from ..schemas import DeviceHeartbeatIn, DeviceRegisterIn
from ..services import devices as device_service

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("/register", summary="注册设备并获取设备密钥（仅返回一次）")
def register_device(payload: DeviceRegisterIn, request: Request, db: Session = Depends(get_db)) -> dict:
    enforce(client_ip(request), "devices.register", write=True)
    return device_service.register(db, payload, ip=client_ip(request))


@router.post("/heartbeat", summary="设备心跳")
def heartbeat(
    payload: DeviceHeartbeatIn,
    device: Device = Depends(get_device),
    db: Session = Depends(get_db),
) -> dict:
    return device_service.heartbeat(db, device, payload)
