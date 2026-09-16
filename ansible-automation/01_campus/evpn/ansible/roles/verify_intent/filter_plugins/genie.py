# ============================================================================
# verify_intent / filter_plugins/genie.py
# ============================================================================
# Parses raw CLI text into a structured dict with Genie, without a device
# connection.
#
# Stage 10 collects output through Catalyst Center Command Runner, so there is
# no pyATS connection to a device — only text. Genie parses text directly when
# handed a Device object that was never connected, which is what this does.
#
# Usage in a check:
#   {{ output | genie_parse('show vrf') }}
#
# pyATS is optional: verify_use_genie defaults false and the regex checks stand
# on their own, so a control node without pyATS still runs stage 10 in full.
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
            "Ansible interpreter. Install it with 'pip install genie pyats', "
            "or leave verify_use_genie false to use the regex checks. "
            "Import error: {0}".format(exc)
        )

    device = Device(name="verify_intent", os=os_name)
    device.custom.setdefault("abstraction", {})["order"] = ["os"]

    try:
        parsed = device.parse(command, output=output)
    except Exception as exc:
        # A parser that finds nothing raises rather than returning {}, and an
        # unparsed command is not the same as a failed check — surface which.
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
