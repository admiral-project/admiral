#!/usr/bin/env python3
"""Build the original #295 Harbor fixture around a CLI-provisioned instance.

Run from the installed Harbor package environment. This validation-only helper
does not call a payment provider.
"""

import json
import sys
import time
from datetime import UTC, datetime, timedelta

from app import create_app
from app.admiral_client import AdmiralAPIError, get_customer_app
from app.extensions import db
from app.models import Customer, CustomerApp, Subscription

EMAIL = "rc6-issue295-cli-fixture@example.invalid"


def register():
    app = create_app()
    app.config["TESTING"] = True
    with app.app_context():
        if db.session.query(Customer).filter_by(email=EMAIL).one_or_none():
            raise SystemExit("refusing to overwrite the #295 CLI test customer")
    response = app.test_client().post(
        "/auth/register",
        data={
            "display_name": "RC6 #295 CLI fixture",
            "email": EMAIL,
            "password": "test-only-" + str(time.time_ns()) + "-StrongPassword!",
            "country": "US",
            "accept_terms": "1",
        },
        follow_redirects=False,
    )
    if response.status_code not in {200, 302}:
        raise SystemExit(f"Harbor registration failed with HTTP {response.status_code}")
    with app.app_context():
        customer = db.session.query(Customer).filter_by(email=EMAIL).one_or_none()
        if not customer or not customer.public_id.startswith("hcus_"):
            raise SystemExit("registration did not create a Harbor customer ID")
        customer.signup_status = "active"
        customer.is_active = True
        customer.reviewed_at = datetime.now(UTC)
        customer.reviewed_by = "issue-295-cli-validation"
        db.session.commit()
        print(json.dumps({"registration_status": response.status_code,
                          "customer_id": customer.public_id,
                          "customer_id_generated_by_harbor": True}, sort_keys=True))


def fixture(customer_id, instance_id):
    app = create_app()
    with app.app_context():
        customer = db.session.query(Customer).filter_by(public_id=customer_id).one_or_none()
        if not customer or customer.email != EMAIL:
            raise SystemExit("refusing to attach fixture to an unrelated customer")
        if db.session.query(Subscription).filter_by(customer_email=customer.email).one_or_none():
            raise SystemExit("refusing to overwrite an existing subscription")
        date = (datetime.now(UTC).date() + timedelta(days=7)).isoformat()
        sub = Subscription(customer_email=customer.email, app_slug="e2e-whoami",
                           status="cancelled", instance_id=instance_id,
                           paypal_subscription_id=None, tier_name="small",
                           total_cents=500, next_billing_at=date)
        db.session.add(sub)
        db.session.flush()
        db.session.add(CustomerApp(subscription_id=sub.id,
                                   customer_email=customer.email,
                                   instance_id=instance_id, app_slug="e2e-whoami",
                                   domain="issue295-cli-fixture.example.invalid",
                                   status="running", commercial_status="cancelled",
                                   next_billing_at=date))
        db.session.commit()
        inspect(customer_id)
        try:
            remote = get_customer_app(instance_id, customer_id)
            read_status = "PASS" if remote.get("id") == instance_id else "FAIL: wrong instance"
        except AdmiralAPIError as exc:
            read_status = "FAIL: " + str(exc)
        print(json.dumps({"provisioned_via_cli": True,
                          "customer_scoped_read": read_status,
                          "instance_id": instance_id}, sort_keys=True))


def expire(customer_id, instance_id):
    app = create_app()
    with app.app_context():
        customer = db.session.query(Customer).filter_by(public_id=customer_id).one_or_none()
        sub = db.session.query(Subscription).filter_by(customer_email=EMAIL).one_or_none()
        local = db.session.query(CustomerApp).filter_by(instance_id=instance_id).one_or_none()
        if (not customer or customer.public_id != customer_id or not sub or not local
                or sub.instance_id != instance_id):
            raise SystemExit("refusing to expire an unrelated or incomplete fixture")
        date = (datetime.now(UTC).date() - timedelta(days=1)).isoformat()
        sub.next_billing_at = date
        local.next_billing_at = date
        db.session.commit()
    inspect(customer_id)


def inspect(customer_id):
    app = create_app()
    with app.app_context():
        customer = db.session.query(Customer).filter_by(public_id=customer_id).one_or_none()
        if not customer or customer.email != EMAIL:
            raise SystemExit("test customer missing")
        sub = db.session.query(Subscription).filter_by(customer_email=customer.email).one_or_none()
        local = db.session.query(CustomerApp).filter_by(instance_id=sub.instance_id).one_or_none() if sub else None
        print(json.dumps({"customer_id": customer.public_id,
                          "signup_status": customer.signup_status,
                          "subscription_status": sub.status if sub else None,
                          "subscription_next_billing_at": sub.next_billing_at if sub else None,
                          "paypal_subscription_id_present": bool(sub and sub.paypal_subscription_id),
                          "instance_id": sub.instance_id if sub else None,
                          "technical_status": local.status if local else None,
                          "commercial_status": local.commercial_status if local else None,
                          "app_next_billing_at": local.next_billing_at if local else None},
                         sort_keys=True))


def cleanup(customer_id):
    app = create_app()
    with app.app_context():
        customer = db.session.query(Customer).filter_by(public_id=customer_id).one_or_none()
        if not customer or customer.email != EMAIL:
            raise SystemExit("refusing to delete an unrelated customer")
        sub = db.session.query(Subscription).filter_by(customer_email=customer.email).one_or_none()
        if sub:
            local = db.session.query(CustomerApp).filter_by(instance_id=sub.instance_id).one_or_none()
            if local:
                db.session.delete(local)
            db.session.delete(sub)
        db.session.delete(customer)
        db.session.commit()
        print(json.dumps({"cleanup": "complete", "customer_id": customer_id}, sort_keys=True))


if len(sys.argv) == 2 and sys.argv[1] == "register":
    register()
elif len(sys.argv) == 4 and sys.argv[1] == "attach":
    fixture(sys.argv[2], sys.argv[3])
elif len(sys.argv) == 4 and sys.argv[1] == "expire":
    expire(sys.argv[2], sys.argv[3])
elif len(sys.argv) == 3 and sys.argv[1] == "inspect":
    inspect(sys.argv[2])
elif len(sys.argv) == 3 and sys.argv[1] == "cleanup":
    cleanup(sys.argv[2])
else:
    raise SystemExit("usage: issue-295-cli-fixture.py register | attach CUSTOMER_ID INSTANCE_ID | expire CUSTOMER_ID INSTANCE_ID | inspect CUSTOMER_ID | cleanup CUSTOMER_ID")
