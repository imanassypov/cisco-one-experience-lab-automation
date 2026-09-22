# ============================================================================
# verify_intent / filter_plugins/genie.py
# ============================================================================
# Parses raw CLI text into a structured dict with Genie, without a device
# connection.
#
# Stage 12 collects output through Catalyst Center Command Runner, so there is
# no pyATS connection to a device — only text.
#
# That is fine, because device.parse(command, output=text) never touches the
# network: handing it output= tells Genie to parse the string it was given. The
# Device here is not a connection, it is how Genie finds the parser.
#
# Genie does not detect the os — it is declared. os_name below is the only
# source, every call site takes its 'iosxe' default, and that is correct for
# all of them: the fabric switches and the 9800 controller all run IOS-XE.
# Genie resolves the parser for 'show vrf' out of the library for that os, so
# the Device is metadata for that lookup and is never connected.
#
# Usage in a check:
#   {{ output | genie_parse('show vrf') }}
#
# pyATS is a hard dependency of stage 12 since every check is structured;
# 00_scriptserver_bootstrap installs it. See vars/checks.yml.
# ============================================================================
import json

from ansible.errors import AnsibleFilterError


def genie_parse(output, command, os_name="iosxe"):
    """Parse CLI text with Genie and return plain Python types."""
    try:
        from genie.conf.base import Device
    except ImportError as exc:
        raise AnsibleFilterError(
            "genie_parse needs pyATS/Genie, which is not installed in the "
            "Ansible interpreter. Stage 12 parses every command, so this is a "
            "hard dependency: run 00_scriptserver_bootstrap, or "
            "'pip install genie pyats' into the venv running Ansible. "
            "Import error: {0}".format(exc)
        )

    device = Device(name="verify_intent", os=os_name)
    # Resolve the parser from os alone. Anything richer (platform, model) is
    # only known from a live connection, which this device will never have.
    device.custom.setdefault("abstraction", {})["order"] = ["os"]

    # Command Runner hands back the command itself as the first line, the way a
    # switch echoes what you typed. Most parsers skip past it, but the telemetry
    # one reads it as the entire output and finds nothing, so drop it here.
    lines = output.splitlines()
    if lines and lines[0].strip() == command.strip():
        output = "\n".join(lines[1:])

    # Genie signals "the command ran but there was nothing to parse" by raising
    # rather than returning {}. Imported defensively because the module path has
    # moved between Genie releases; the class-name check below is the fallback.
    try:
        from genie.metaparser.util.exceptions import SchemaEmptyParserError
    except ImportError:
        SchemaEmptyParserError = ()

    try:
        parsed = device.parse(command, output=output)
    except Exception as exc:
        # An empty parse is a real device state, not a tooling failure: a fabric
        # with no NVE peers or a controller with no APs genuinely has nothing to
        # report. Return {} so the check reports 'absent' and fails on its own
        # terms, instead of aborting the whole run.
        if isinstance(exc, SchemaEmptyParserError) or \
                type(exc).__name__ == "SchemaEmptyParserError":
            return {}
        raise AnsibleFilterError(
            "Genie could not parse '{0}' for os '{1}': {2}: {3}".format(
                command, os_name, type(exc).__name__, exc
            )
        )

    # Converting through JSON hands Ansible ordinary values it can use. Doing so
    # turns every lookup name into text, so a VLAN, VNI or subscription number
    # must be looked up as "40101", not 40101 — write `| string` in the check.
    return json.loads(json.dumps(parsed))


class FilterModule(object):
    def filters(self):
        return {"genie_parse": genie_parse}
