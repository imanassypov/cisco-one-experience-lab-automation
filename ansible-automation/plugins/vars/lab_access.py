# Copyright (c) 2026 Cisco One Experience Lab Automation
# SPDX-License-Identifier: MIT
"""Load Lab Topology/lab_access.yml (Ansible Vault) into ``lab_access``."""
from __future__ import annotations

import os

from ansible.errors import AnsibleParserError
from ansible.plugins.vars import BaseVarsPlugin
from ansible.utils.display import Display

display = Display()

LOOKUP_DIRNAME = "Lab Topology"
LOOKUP_FILENAME = "lab_access.yml"
MAX_WALK_DEPTH = 12


def _find_lab_access(start):
    current = os.path.abspath(start)
    for _ in range(MAX_WALK_DEPTH):
        candidate = os.path.join(current, LOOKUP_DIRNAME, LOOKUP_FILENAME)
        if os.path.isfile(candidate):
            return os.path.realpath(candidate)
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent
    return None


class VarsModule(BaseVarsPlugin):
    """Inject the vault-encrypted lab access map for every host and group."""

    REQUIRES_ENABLED = False
    is_stateless = True

    def get_vars(self, loader, path, entities, cache=True):
        del entities, cache
        start = path or os.getcwd()
        vault_path = _find_lab_access(start)
        if vault_path is None:
            vault_path = _find_lab_access(os.getcwd())
        if vault_path is None:
            raise AnsibleParserError(
                "Lab access vault not found. Expected "
                f"{LOOKUP_DIRNAME}/{LOOKUP_FILENAME} above {start}. "
                "Create it from Lab Topology/lab_access.yml.example and encrypt "
                "with ansible-vault. Unlock it with this collection's .vault."
            )
        if os.path.basename(vault_path) != LOOKUP_FILENAME:
            raise AnsibleParserError("Refusing to load unexpected lab access filename.")

        data = loader.load_from_file(vault_path)
        if not isinstance(data, dict) or "lab_access" not in data:
            raise AnsibleParserError(
                f"{vault_path} must decrypt to a mapping with a top-level lab_access key."
            )
        display.vv(f"Loaded lab_access from {vault_path}")
        return {"lab_access": data["lab_access"]}
