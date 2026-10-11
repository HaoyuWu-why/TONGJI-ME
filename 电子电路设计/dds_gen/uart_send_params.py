"""Send one DDS parameter frame to the FPGA over a 115200-8N1 UART."""

from __future__ import annotations

import argparse


WAVES = {"sine": 0, "square": 1, "triangle": 2, "saw": 3}


def build_frame(wave: str, frequency_hz: int, amplitude: int) -> bytes:
    if wave not in WAVES:
        raise ValueError(f"wave must be one of: {', '.join(WAVES)}")
    if not 100 <= frequency_hz <= 10_000 or frequency_hz % 100:
        raise ValueError("frequency must be 100..10000 Hz in 100 Hz steps")
    if not 0 <= amplitude <= 255:
        raise ValueError("amplitude must be 0..255")

    payload = bytes((0xA5, WAVES[wave], frequency_hz // 100, amplitude))
    checksum = payload[0] ^ payload[1] ^ payload[2] ^ payload[3]
    return payload + bytes((checksum,))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="serial port, for example COM3")
    parser.add_argument("wave", choices=WAVES)
    parser.add_argument("frequency_hz", type=int)
    parser.add_argument("amplitude", type=int)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the frame without opening the serial port",
    )
    args = parser.parse_args()

    frame = build_frame(args.wave, args.frequency_hz, args.amplitude)
    print("frame:", " ".join(f"{value:02X}" for value in frame))
    if args.dry_run:
        return

    try:
        import serial
    except ImportError as exc:
        raise SystemExit("Install pyserial first: python -m pip install pyserial") from exc

    with serial.Serial(args.port, 115200, bytesize=8, parity="N", stopbits=1) as uart:
        uart.write(frame)
        uart.flush()
    print(f"sent {len(frame)} bytes to {args.port}")


if __name__ == "__main__":
    main()
