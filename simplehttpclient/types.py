from dataclasses import dataclass
from typing import Optional

@dataclass
class Request:
    path: str
    data: Optional[bytes]

@dataclass
class Response:
    code: int
    data: Optional[bytes]
