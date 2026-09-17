# ============================================================================
# verify_intent / filter_plugins/genie.py
# ============================================================================
# Parses raw CLI text into a structured dict with Genie, without a device
# connection.
#
# Stage 11 collects output through Catalyst Center Command Runner, so there is
# no pyATS connection to a device — only text. Genie parses text directly when
# handed a Device object that was never connected, which is what this does.
#
# Usage in a check:
#   {{ output | genie_parse('show vrf') }}
#
# pyATS is a hard dependency of stage 11 since every check is structured;
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
            "Ansible interpreter. Stage 11 parses every command, so this is a "
            "hard dependency: run 00_scriptserver_bootstrap, or "
            "'pip install genie pyats' into the venv running Ansible. "
            "Import error: {0}".format(exc)
        )

    device = Device(name="verify_intent", os=os_name)
    device.custom.setdefault("abstraction", {})["order"] = ["os"]

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

    # Genie returns dict subclasses; round-tripping gives Ansible plain types.
    return json.loads(json.dumps(parsed))


class FilterModule(object):
    def filters(self):
        return {"genie_parse": genie_parse}
