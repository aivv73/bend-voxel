import json

from megascene_bend import run


def option(value):
    return "0" if value is None else "1" + value if isinstance(value, str) else "2"


def number(value):
    return value if isinstance(value, str) else "!invalid type"


def policy(operation, args):
    values = (args.case, option(args.preset), option(args.side_m), number(args.seed),
              number(args.threads), number(args.fragment_budget), option(args.additional_allowance),
              option(args.campaign), option(args.archive),
              str(bool(args.capture_opening)).lower(), str(bool(args.validation_only)).lower(),
              option(args.validated), option(args.runtime_from),
              option(args.calibration_peer_validation), option(args.deadline),
              option(args.diagnostic), option(args.resolution), option(args.profile),
              option(args.schedule), option(args.frames), option(args.warmup),
              option(args.calibration), option(args.search))
    return json.loads(run("megascene_configuration", operation, *values))
