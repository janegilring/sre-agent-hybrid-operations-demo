"""Exercise installed Azure CLI validation/filtering with only transport replaced."""
import argparse
import json
import socket
import sys
from types import SimpleNamespace
from unittest.mock import patch

from azure.cli.command_modules.role import custom
from azure.core.paging import ItemPaged
from azure.mgmt.authorization.models import RoleAssignment
from knack.util import CLIError


def no_network(*args, **kwargs):
    raise AssertionError("Network/authentication must not be used in offline tests")


def assignment(identifier, scope):
    role = RoleAssignment()
    role.id = identifier
    role.scope = scope
    return role


def run(arguments):
    parser = argparse.ArgumentParser()
    parser.add_argument("--subscription", required=True)
    parser.add_argument("--scope", required=True)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--fill-principal-name", choices=["false"], required=True)
    parser.add_argument("--fill-role-definition-name", choices=["false"], required=True)
    parser.add_argument("--only-show-errors", action="store_true")
    parser.add_argument("--output", choices=["json"], required=True)
    assert arguments[:3] == ["role", "assignment", "list"]
    args = parser.parse_args(arguments[3:])
    visited = []

    def list_for_scope(scope, filter):
        assert scope == args.scope and filter == "atScope()"
        # Genuine SDK pagination: an inherited assignment and more than one page
        # of exact-scope assignments. The last page must not be dropped.
        pages = [
            [assignment("inherited", "/subscriptions/" + args.subscription)]
            + [assignment(str(i), scope) for i in range(100)],
            [assignment("last-page", scope.upper()),
             assignment("foreign", scope + "/foreign")],
        ]

        def get_next(token):
            index = int(token or 0)
            visited.append(index)
            return index

        def extract_data(index):
            return (str(index + 1) if index + 1 < len(pages) else None, pages[index])

        return ItemPaged(get_next, extract_data)

    auth = SimpleNamespace(
        role_assignments=SimpleNamespace(list_for_scope=list_for_scope),
        role_definitions=SimpleNamespace(_config=SimpleNamespace(subscription_id=args.subscription)),
    )
    with patch.object(custom, "_graph_client_factory", return_value=object()), \
         patch.object(custom, "_auth_client_factory", return_value=auth):
        kwargs = dict(scope=args.scope, show_all=args.all,
                      fill_principal_name=False, fill_role_definition_name=False)
        cmd = SimpleNamespace(cli_ctx=None)
        # The installed command's actual argument validator, not a duplicate rule.
        try:
            custom.list_role_assignments(cmd, **dict(kwargs, show_all=True))
        except CLIError as error:
            assert "group or scope are not required when --all is used" in str(error)
        else:
            raise AssertionError("Old invalid scope + all combination was accepted")
        result = custom.list_role_assignments(cmd, **kwargs)
        assert visited == [0, 1], visited
        assert len(result) == 101, len(result)
        assert result[-1]["id"] == "last-page"
        assert not {"inherited", "foreign"} & {role["id"] for role in result}


with open(sys.argv[1], encoding="utf-8-sig") as file:
    calls = json.load(file)
with patch.object(socket.socket, "connect", no_network), \
     patch.object(socket, "create_connection", no_network):
    for call in calls:
        run(call)
print(f"PASS: {len(calls)} production CLI argument sets; real installed validator "
      "rejects --scope + --all; real SDK two-page iteration and exact-scope filtering. "
      "Transport factories replaced; no profile, authentication or network.")
