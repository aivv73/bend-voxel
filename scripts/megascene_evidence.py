"""Typed transport between retained Python evidence and Bend policy workers."""

from megascene_bend import run_input
from megascene_scale import _decimal, _integer


def _signed_decimal(value):
    return ("-" if value < 0 else "") + _decimal(abs(value))


def _signed_integer(value):
    return -_integer(value[1:]) if value.startswith("-") else _integer(value)


def _text(value):
    return "".join(format(ord(character), "06x") for character in value)


def _untext(value):
    if len(value) % 6:
        raise ValueError("malformed evidence text")
    return "".join(chr(int(value[index:index + 6], 16))
                   for index in range(0, len(value), 6))


def encode(value):
    lines = []

    def visit(item):
        if item is None:
            lines.append("n")
        elif type(item) is bool:
            lines.append("b1" if item else "b0")
        elif type(item) is int:
            lines.append("i" + _signed_decimal(item))
        elif type(item) is float:
            lines.append("f" + item.hex() + "/" + repr(item))
        elif isinstance(item, str):
            lines.append("s" + _text(item))
        elif isinstance(item, (list, tuple)):
            for child in item:
                visit(child)
            lines.append("a" + str(len(item)))
        elif isinstance(item, dict):
            for key, child in item.items():
                if not isinstance(key, str):
                    raise TypeError("evidence object keys must be strings")
                visit(key)
                visit(child)
            lines.append("o" + str(len(item)))
        else:
            raise TypeError("unsupported evidence transport type")

    visit(value)
    return "\n".join(lines) + "\n"


def decode(text):
    stack = []
    for line in text.splitlines():
        if line == "n":
            stack.append(None)
        elif line == "b0":
            stack.append(False)
        elif line == "b1":
            stack.append(True)
        elif line.startswith("i"):
            stack.append(_signed_integer(line[1:]))
        elif line.startswith("f"):
            value, _ = line[1:].split("/", 1)
            stack.append(float.fromhex(value))
        elif line.startswith("s"):
            stack.append(_untext(line[1:]))
        elif line.startswith("e"):
            message = _untext(line[1:])
            if message.startswith("missing field:"):
                raise KeyError(message[len("missing field:"):])
            if message.startswith("type error:"):
                raise TypeError(message[len("type error:"):])
            raise ValueError(message)
        elif line == "d":
            if len(stack) < 2:
                raise ValueError("evidence division stack underflow")
            right, left = stack.pop(), stack.pop()
            stack.append(left / right)
        elif line.startswith("r"):
            numerator, denominator = line[1:].split("/", 1)
            stack.append(_signed_integer(numerator) / _integer(denominator))
        elif line.startswith(("a", "o")):
            size = int(line[1:])
            width = size * (2 if line[0] == "o" else 1)
            if size < 0 or width > len(stack):
                raise ValueError("evidence container stack underflow")
            values = stack[len(stack) - width:] if width else []
            if width:
                del stack[-width:]
            if line[0] == "a":
                stack.append(values)
            else:
                if any(not isinstance(key, str) for key in values[::2]):
                    raise ValueError("evidence object keys must be strings")
                pairs = list(zip(values[::2], values[1::2]))
                if len({key for key, _ in pairs}) != len(pairs):
                    raise ValueError("duplicate evidence object key")
                stack.append(dict(pairs))
        else:
            raise ValueError("malformed evidence token")
    if len(stack) != 1:
        raise ValueError("malformed evidence root")
    return stack[0]


def run(operation, payload, module="evidence_report"):
    return decode(run_input(module, encode({"operation": operation, "payload": payload})))
