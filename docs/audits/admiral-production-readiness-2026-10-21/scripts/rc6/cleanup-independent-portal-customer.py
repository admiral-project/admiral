#!/usr/bin/env python3
"""Delete one finished synthetic customer flow from the disposable Harbor DB."""

from __future__ import annotations

import json
import sys

from app import create_app
from app.extensions import db
from app.models import Customer, CustomerApp, Subscription


def main() -> int:
    if len(sys.argv) != 2 or "@example.test" not in sys.argv[1]:
        raise SystemExit("usage: cleanup-independent-portal-customer.py TEST_EMAIL@example.test")
    email = sys.argv[1]
    app = create_app()
    with app.app_context():
        customer = db.session.query(Customer).filter_by(email=email).one_or_none()
        if customer is None:
            print(json.dumps({"cleanup": "already_absent", "email": email}, sort_keys=True))
            return 0
        apps = db.session.query(CustomerApp).filter_by(customer_email=email).all()
        unsafe = [row for row in apps if row.status not in {"deprovisioned", "deleted", "cancelled"}]
        if unsafe:
            raise SystemExit("refusing to delete a Harbor customer with a nonterminal app")
        subscriptions = db.session.query(Subscription).filter_by(customer_email=email).all()
        for row in apps:
            db.session.delete(row)
        for row in subscriptions:
            db.session.delete(row)
        db.session.delete(customer)
        db.session.commit()
        print(
            json.dumps(
                {"cleanup": "complete", "email": email, "apps_removed": len(apps), "subscriptions_removed": len(subscriptions)},
                sort_keys=True,
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
