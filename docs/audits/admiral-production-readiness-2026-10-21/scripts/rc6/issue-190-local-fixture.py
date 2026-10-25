#!/usr/bin/env python3
"""Create, inspect, expire, or remove the local Harbor #190 test fixture.

Run with the installed Harbor environment and working directory so the exact
packaged ORM models and PostgreSQL database are exercised. This fixture does
not create or contact any payment-provider subscription.
"""

import json
import os
import sys
from datetime import UTC, datetime, timedelta

from app import create_app
from app.extensions import db
from app.models import Customer, CustomerApp, Subscription

CUSTOMER_ID = os.environ.get("HARBOR190_CUSTOMER_ID", "harbor190-rc6-fedora-20261025")
EMAIL = os.environ.get("HARBOR190_CUSTOMER_EMAIL", "harbor190-rc6-fedora-20261025@example.invalid")
INSTANCE_ID = os.environ.get("HARBOR190_INSTANCE_ID", "inst_e624b833202b711c")


def main(action):
    app = create_app()
    with app.app_context():
        customer = db.session.query(Customer).filter_by(public_id=CUSTOMER_ID).one_or_none()
        subscription = db.session.query(Subscription).filter_by(instance_id=INSTANCE_ID).one_or_none()
        local_app = db.session.query(CustomerApp).filter_by(instance_id=INSTANCE_ID).one_or_none()

        if action == "seed":
            if customer or subscription or local_app:
                raise SystemExit("refusing to overwrite an existing #190 fixture")
            customer = Customer(
                email=EMAIL,
                public_id=CUSTOMER_ID,
                display_name="RC6 Harbor worker validation",
                password_hash="not-a-login-fixture",
                signup_status="active",
            )
            db.session.add(customer)
            db.session.flush()
            prepaid_end = (datetime.now(UTC).date() + timedelta(days=7)).isoformat()
            subscription = Subscription(
                customer_email=EMAIL,
                app_slug="e2e-whoami",
                status="cancelled",
                instance_id=INSTANCE_ID,
                paypal_subscription_id=None,
                tier_name="small",
                total_cents=500,
                next_billing_at=prepaid_end,
            )
            db.session.add(subscription)
            db.session.flush()
            local_app = CustomerApp(
                subscription_id=subscription.id,
                customer_email=EMAIL,
                instance_id=INSTANCE_ID,
                app_slug="e2e-whoami",
                domain="harbor190-rc6-fedora.example.invalid",
                status="running",
                commercial_status="cancelled",
                next_billing_at=prepaid_end,
            )
            db.session.add(local_app)
            db.session.commit()
        elif action == "expire":
            if not subscription or not local_app:
                raise SystemExit("#190 fixture is missing")
            expired = (datetime.now(UTC).date() - timedelta(days=1)).isoformat()
            subscription.next_billing_at = expired
            local_app.next_billing_at = expired
            db.session.commit()
        elif action == "cleanup":
            if local_app:
                db.session.delete(local_app)
            if subscription:
                db.session.delete(subscription)
            if customer:
                db.session.delete(customer)
            db.session.commit()
            print(json.dumps({"cleanup": "complete", "instance_id": INSTANCE_ID}, sort_keys=True))
            return
        elif action != "inspect":
            raise SystemExit("usage: issue-190-local-fixture.py {seed|inspect|expire|cleanup}")

        db.session.refresh(customer) if customer else None
        db.session.refresh(subscription) if subscription else None
        db.session.refresh(local_app) if local_app else None
        if not customer or not subscription or not local_app:
            print(json.dumps({"fixture": "missing", "instance_id": INSTANCE_ID}, sort_keys=True))
            return
        print(
            json.dumps(
                {
                    "customer_id": customer.public_id,
                    "customer_email": customer.email,
                    "subscription_status": subscription.status,
                    "paypal_subscription_id_present": subscription.paypal_subscription_id is not None,
                    "subscription_next_billing_at": subscription.next_billing_at,
                    "instance_id": local_app.instance_id,
                    "technical_status": local_app.status,
                    "commercial_status": local_app.commercial_status,
                    "app_next_billing_at": local_app.next_billing_at,
                },
                sort_keys=True,
            )
        )


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) == 2 else "")
