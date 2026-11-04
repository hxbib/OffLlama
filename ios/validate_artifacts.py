#!/usr/bin/env python3
"""Strict, portable validation for Pocket Glimmer shipping artifacts.

Used by ios/mac_prep.sh and tested on Linux and macOS. It mirrors the value
types and shipping checks in core/Sources/PocketCore/Calibration.swift,
core/Sources/PocketCore/Skills.swift, and AppModel.bootOnce. It never uses
plutil -p text output.

Commands (each prints a single-line error and exits 1 on failure):
  calibration FILE EXPECTED_SHA256
  skills FILE
  entitlements FILE
  xcframework-plist FILE
  slice-plist FILE
  provenance MARKER EXPECTED_COMMIT FRAMEWORK_DIR
  framework-digest FRAMEWORK_DIR
  macho FILE
"""
import hashlib
import json
import math
import os
import plistlib
import struct
import sys

CALIBRATION_SHA256 = "b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1"
STATIC_PRIOR_LENGTHS = {
    "route": 4,
    "toolChoice": 7,
    "rememberOrNot": 3,
    "memoryConflict": 3,
    "notificationTriage": 3,
    "confirmBeforeAct": 2,
    "nudgeNow": 3,
    "timing": 4,
    "sensitivity": 2,
    "answerability": 2,
}
DYNAMIC_TYPES = ("contactPick", "eventPick", "skillPick")
DECISION_TYPES = set(STATIC_PRIOR_LENGTHS) | set(DYNAMIC_TYPES)
EXPECTED_PRIORS = dict(STATIC_PRIOR_LENGTHS)
for _kind in DYNAMIC_TYPES:
    for _n in range(2, 9):
        EXPECTED_PRIORS["%s#%d" % (_kind, _n)] = _n
CALIBRATION_KEYS = {"defaultTau", "prior", "promptStyle", "tau", "temperature"}

SKILL_CATEGORIES = {
    "message", "social", "email", "calendar", "reminders", "alarms", "phone",
    "documents", "shortcuts", "device", "memory", "web",
}
ARG_KINDS = {
    "contact", "handle", "text", "datetime", "url", "document", "app",
    "duration", "number", "place", "query",
}
INVOCATION_TYPES = {"url", "shortcut", "native", "cloud"}
CLOUD_REASONS = {"needsOnline", "longContext", "generation"}
SKILL_KEYS = {
    "id", "title", "category", "invocation", "argSchema", "confirm",
    "offlineCapable", "examples", "aliases", "clipboard", "note",
}
ARG_KEYS = {"name", "kind", "required"}
INVOCATION_KEYS = {
    "url": {"type", "template"},
    "shortcut": {"type", "name", "input"},
    "native": {"type", "handler"},
    "cloud": {"type", "kind"},
}


class Invalid(Exception):
    pass


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def _no_duplicates(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise Invalid("duplicate JSON key %r" % key)
        out[key] = value
    return out


def _reject_constant(value):
    raise Invalid("non-finite JSON number %r" % value)


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle, object_pairs_hook=_no_duplicates,
                             parse_constant=_reject_constant)
    except Invalid:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Invalid("not readable JSON: %s" % exc)


def load_plist(path):
    try:
        with open(path, "rb") as handle:
            return plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError) as exc:
        raise Invalid("not a readable property list: %s" % exc)


def is_number(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value))


def check_number(value, what):
    if not is_number(value):
        raise Invalid("%s must be a finite JSON number" % what)


def check_calibration(path, expected_sha256):
    data = load_json(path)
    if not isinstance(data, dict):
        raise Invalid("top level must be a JSON object")
    unknown = sorted(set(data) - CALIBRATION_KEYS)
    missing = sorted(CALIBRATION_KEYS - set(data))
    if missing:
        raise Invalid("missing top-level key(s): %s" % ", ".join(missing))
    if unknown:
        raise Invalid("unexpected top-level key(s): %s" % ", ".join(unknown))

    check_number(data["defaultTau"], "defaultTau")
    if data["defaultTau"] != 0.9:
        raise Invalid("defaultTau is %r; the certified operating point is 0.9" % data["defaultTau"])
    if data["promptStyle"] != "fewShot":
        raise Invalid("promptStyle must be \"fewShot\", not %r" % (data["promptStyle"],))

    for field, expected in (("tau", 0.9), ("temperature", 1.0)):
        table = data[field]
        if not isinstance(table, dict):
            raise Invalid("%s must be a JSON object" % field)
        for key, value in table.items():
            if key not in DECISION_TYPES:
                raise Invalid("%s has unknown decision type %r" % (field, key))
            check_number(value, "%s[%r]" % (field, key))
            if value != expected:
                raise Invalid("%s[%r] is %r; every value must be %s" %
                              (field, key, value, expected))

    prior = data["prior"]
    if not isinstance(prior, dict):
        raise Invalid("prior must be a JSON object")
    missing = sorted(set(EXPECTED_PRIORS) - set(prior))
    unexpected = sorted(set(prior) - set(EXPECTED_PRIORS))
    if missing:
        raise Invalid("missing prior set(s): %s" % ", ".join(missing))
    if unexpected:
        raise Invalid("unexpected prior set(s): %s" % ", ".join(unexpected))
    for key in sorted(EXPECTED_PRIORS):
        values = prior[key]
        if not isinstance(values, list):
            raise Invalid("prior[%r] must be an array of numbers" % key)
        if len(values) != EXPECTED_PRIORS[key]:
            raise Invalid("prior[%r] has %d value(s); expected %d" %
                          (key, len(values), EXPECTED_PRIORS[key]))
        for index, value in enumerate(values):
            check_number(value, "prior[%r][%d]" % (key, index))

    digest = sha256_file(path)
    if digest != expected_sha256:
        raise Invalid("sha256 is %s; the shipping calibration must stay byte-identical to %s" %
                      (digest, expected_sha256))

    return "promptStyle=fewShot, defaultTau=0.90, %d prior sets, sha256 verified" % len(prior)


def require_plain_string(value, what, nonempty=True):
    if not isinstance(value, str):
        raise Invalid("%s must be a JSON string" % what)
    if nonempty and not value.strip():
        raise Invalid("%s must not be empty" % what)


def check_string_list(value, what):
    if not isinstance(value, list) or any(not isinstance(v, str) for v in value):
        raise Invalid("%s must be an array of strings" % what)


def check_invocation(value, where):
    if not isinstance(value, dict):
        raise Invalid("%s must be a JSON object" % where)
    kind = value.get("type")
    if kind not in INVOCATION_TYPES:
        raise Invalid("%s.type must be one of %s" % (where, ", ".join(sorted(INVOCATION_TYPES))))
    extra = sorted(set(value) - INVOCATION_KEYS[kind])
    if extra:
        raise Invalid("%s has unexpected key(s) for type %s: %s" %
                      (where, kind, ", ".join(extra)))
    if kind == "url":
        require_plain_string(value.get("template"), where + ".template")
    elif kind == "shortcut":
        require_plain_string(value.get("name"), where + ".name")
        if "input" in value and value["input"] is not None:
            require_plain_string(value["input"], where + ".input", nonempty=False)
    elif kind == "native":
        require_plain_string(value.get("handler"), where + ".handler")
    else:
        if value.get("kind") not in CLOUD_REASONS:
            raise Invalid("%s.kind must be one of %s" %
                          (where, ", ".join(sorted(CLOUD_REASONS))))


def check_skill(skill, index):
    where = "skills[%d]" % index
    if not isinstance(skill, dict):
        raise Invalid("%s must be a JSON object" % where)
    extra = sorted(set(skill) - SKILL_KEYS)
    if extra:
        raise Invalid("%s has unexpected key(s): %s" % (where, ", ".join(extra)))
    require_plain_string(skill.get("id"), where + ".id")
    require_plain_string(skill.get("title"), where + ".title")
    if skill.get("category") not in SKILL_CATEGORIES:
        raise Invalid("%s.category must be one of %s" %
                      (where, ", ".join(sorted(SKILL_CATEGORIES))))
    check_invocation(skill.get("invocation"), where + ".invocation")

    args = skill.get("argSchema", [])
    if not isinstance(args, list):
        raise Invalid("%s.argSchema must be an array" % where)
    names = set()
    for arg_index, arg in enumerate(args):
        arg_where = "%s.argSchema[%d]" % (where, arg_index)
        if not isinstance(arg, dict):
            raise Invalid("%s must be a JSON object" % arg_where)
        extra = sorted(set(arg) - ARG_KEYS)
        if extra:
            raise Invalid("%s has unexpected key(s): %s" % (arg_where, ", ".join(extra)))
        require_plain_string(arg.get("name"), arg_where + ".name")
        if arg["name"] in names:
            raise Invalid("%s has duplicate arg name %r" % (where, arg["name"]))
        names.add(arg["name"])
        if arg.get("kind") not in ARG_KINDS:
            raise Invalid("%s.kind must be one of %s" %
                          (arg_where, ", ".join(sorted(ARG_KINDS))))
        if "required" in arg and not isinstance(arg["required"], bool):
            raise Invalid("%s.required must be a boolean" % arg_where)

    for key in ("examples", "aliases"):
        if key in skill:
            check_string_list(skill[key], where + "." + key)
    for key in ("confirm", "offlineCapable"):
        if key in skill and not isinstance(skill[key], bool):
            raise Invalid("%s.%s must be a boolean" % (where, key))
    for key in ("clipboard", "note"):
        if key in skill and skill[key] is not None:
            require_plain_string(skill[key], where + "." + key, nonempty=False)


def check_skills(path):
    data = load_json(path)
    if not isinstance(data, dict):
        raise Invalid("top level must be a JSON object with a skills array")
    extra = sorted(set(data) - {"skills"})
    if extra:
        raise Invalid("unexpected top-level key(s): %s" % ", ".join(extra))
    skills = data.get("skills")
    if not isinstance(skills, list) or not skills:
        raise Invalid("skills must be a non-empty array")
    seen = set()
    for index, skill in enumerate(skills):
        check_skill(skill, index)
        if skill["id"] in seen:
            raise Invalid("duplicate skill id %r" % skill["id"])
        seen.add(skill["id"])
    return "%d skills, strict schema" % len(skills)


def check_entitlements(path):
    data = load_plist(path)
    if not isinstance(data, dict):
        raise Invalid("entitlements must be a dictionary")
    if data:
        raise Invalid("free-team entitlements must stay empty; found: %s" %
                      ", ".join(sorted(str(k) for k in data)))
    return "empty (free personal team compatible)"


def check_xcframework_plist(path):
    data = load_plist(path)
    if not isinstance(data, dict):
        raise Invalid("xcframework Info.plist must be a dictionary")
    if data.get("CFBundlePackageType") != "XFWK":
        raise Invalid("CFBundlePackageType must be XFWK")
    libraries = data.get("AvailableLibraries")
    if not isinstance(libraries, list) or not libraries:
        raise Invalid("AvailableLibraries must be a non-empty array")
    matches = [entry for entry in libraries
               if isinstance(entry, dict) and entry.get("LibraryIdentifier") == "ios-arm64"]
    if len(matches) != 1:
        raise Invalid("AvailableLibraries must contain exactly one ios-arm64 device slice")
    entry = matches[0]
    if entry.get("LibraryPath") != "llama.framework":
        raise Invalid("AvailableLibraries ios-arm64 LibraryPath must be llama.framework")
    if entry.get("SupportedPlatform") != "ios":
        raise Invalid("AvailableLibraries ios-arm64 SupportedPlatform must be ios")
    if entry.get("SupportedPlatformVariant"):
        raise Invalid("AvailableLibraries ios-arm64 must be a device slice, not %r" %
                      entry["SupportedPlatformVariant"])
    architectures = entry.get("SupportedArchitectures")
    if not isinstance(architectures, list) or "arm64" not in architectures:
        raise Invalid("AvailableLibraries ios-arm64 must list arm64")
    return "ios-arm64/llama.framework arm64"


def check_slice_plist(path):
    data = load_plist(path)
    if not isinstance(data, dict):
        raise Invalid("framework Info.plist must be a dictionary")
    if data.get("CFBundleExecutable") != "llama":
        raise Invalid("CFBundleExecutable must be llama")
    if data.get("CFBundlePackageType") != "FMWK":
        raise Invalid("CFBundlePackageType must be FMWK")
    return "llama.framework metadata"


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def framework_source_digest(fw):
    """Digest the headers and module map that a source xcframework exposes."""
    slice_dir = os.path.join(fw, "ios-arm64", "llama.framework")
    roots = [os.path.join(slice_dir, "Headers"), os.path.join(slice_dir, "Modules")]
    files = []
    for root in roots:
        for dirpath, _dirnames, filenames in os.walk(root):
            for name in filenames:
                path = os.path.join(dirpath, name)
                if os.path.isfile(path) and not os.path.islink(path):
                    files.append(path)
    if not files:
        raise Invalid("no headers or module map to digest")
    digest = hashlib.sha256()
    for path in sorted(files, key=lambda p: os.path.relpath(p, fw)):
        relative = os.path.relpath(path, fw).replace(os.sep, "/")
        digest.update(relative.encode("utf-8") + b"\0")
        with open(path, "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        digest.update(b"\0")
    return digest.hexdigest()


def check_provenance(marker, expected_commit, fw):
    data = load_json(marker)
    if not isinstance(data, dict):
        raise Invalid("provenance marker must be a JSON object")
    if data.get("commit") != expected_commit:
        raise Invalid("provenance commit is %r; expected %s" %
                      (data.get("commit"), expected_commit))
    if data.get("clean") is not True:
        raise Invalid("provenance does not attest a clean llama.cpp checkout")
    binary = os.path.join(fw, "ios-arm64", "llama.framework", "llama")
    digest = sha256_file(binary)
    if data.get("device_binary_sha256") != digest:
        raise Invalid("provenance binary sha256 does not match %s" % digest)
    source_digest = framework_source_digest(fw)
    if data.get("headers_sha256") != source_digest:
        raise Invalid("provenance headers/module map sha256 does not match %s" % source_digest)
    return "pinned %s, clean, binary %s, source %s" % (
        expected_commit[:12], digest[:12], source_digest[:12])


CPU_TYPE_ARM64 = 0x0100000C
CPU_TYPE_X86_64 = 0x01000007
MH_DYLIB = 6
MH_BUNDLE = 8


def _thin_macho(data, offset=0):
    if len(data) < offset + 28:
        raise Invalid("truncated Mach-O header")
    magic = data[offset:offset + 4]
    if magic == b"\xcf\xfa\xed\xfe":
        endian = "<"
    elif magic == b"\xfe\xed\xfa\xcf":
        endian = ">"
    elif magic in (b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce"):
        raise Invalid("32-bit Mach-O; the app needs arm64")
    else:
        raise Invalid("not a Mach-O binary")
    cputype, _subtype, filetype, _ncmds, _sizeofcmds, _flags = struct.unpack(
        endian + "IIIIII", data[offset + 4:offset + 28])
    return cputype, filetype


def check_macho(path):
    try:
        with open(path, "rb") as handle:
            data = handle.read(4096)
    except OSError as exc:
        raise Invalid("cannot read binary: %s" % exc)
    if len(data) < 28:
        raise Invalid("binary is too small to be a Mach-O framework")
    magic = data[:4]
    if magic in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
        endian = ">" if magic == b"\xca\xfe\xba\xbe" else "<"
        count = struct.unpack(endian + "I", data[4:8])[0]
        if count == 0 or count > 32:
            raise Invalid("invalid universal Mach-O architecture count %d" % count)
        arm = False
        for index in range(count):
            start = 8 + index * 20
            if len(data) < start + 20:
                raise Invalid("truncated universal Mach-O header")
            cputype = struct.unpack(endian + "I", data[start:start + 4])[0]
            if cputype == CPU_TYPE_ARM64:
                arm = True
        if not arm:
            raise Invalid("universal Mach-O has no arm64 slice")
        return "universal Mach-O with arm64"
    cputype, filetype = _thin_macho(data)
    if cputype != CPU_TYPE_ARM64:
        name = "x86_64" if cputype == CPU_TYPE_X86_64 else "0x%08x" % cputype
        raise Invalid("Mach-O architecture is %s; expected arm64" % name)
    if filetype not in (MH_DYLIB, MH_BUNDLE):
        raise Invalid("Mach-O file type is %d; expected a dynamic library" % filetype)
    return "arm64 Mach-O dynamic library"


def main(argv):
    if len(argv) < 2:
        fail("usage: validate_artifacts.py <command> ...")
    command = argv[1]
    try:
        if command == "calibration" and len(argv) == 4:
            detail = check_calibration(argv[2], argv[3])
        elif command == "skills" and len(argv) == 3:
            detail = check_skills(argv[2])
        elif command == "entitlements" and len(argv) == 3:
            detail = check_entitlements(argv[2])
        elif command == "xcframework-plist" and len(argv) == 3:
            detail = check_xcframework_plist(argv[2])
        elif command == "slice-plist" and len(argv) == 3:
            detail = check_slice_plist(argv[2])
        elif command == "provenance" and len(argv) == 5:
            detail = check_provenance(argv[2], argv[3], argv[4])
        elif command == "framework-digest" and len(argv) == 3:
            detail = framework_source_digest(argv[2])
        elif command == "macho" and len(argv) == 3:
            detail = check_macho(argv[2])
        else:
            fail("usage: validate_artifacts.py <calibration|skills|entitlements|"
                 "xcframework-plist|slice-plist|provenance|framework-digest|macho> ...")
    except Invalid as exc:
        fail(str(exc))
    except OSError as exc:
        fail("file error: %s" % exc)
    if detail:
        print(detail)


if __name__ == "__main__":
    main(sys.argv)
