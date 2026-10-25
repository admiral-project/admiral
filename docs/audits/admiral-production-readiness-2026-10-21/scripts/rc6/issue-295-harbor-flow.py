#!/usr/bin/env python3
"""Exercise Harbor-created customer identity against the installed API client.

Run from the installed Harbor RPM with its EnvironmentFile and working
directory. No payment-provider endpoint is called; the cancelled subscription
is a local test fixture with no PayPal subscription ID.
"""

import json
import sys
import time
from datetime import UTC, datetime, timedelta

from app import create_app
from app.admiral_client import AdmiralAPIError, get_customer_app, get_operation, provision_app
from app.extensions import db
from app.models import Customer, CustomerApp, Subscription

EMAIL = "rc6-issue295-harbor-flow@example.invalid"
APP_SLUG = "e2e-whoami"
TIER = "small"


def _fixture(customer_id):
    customer = db.session.query(Customer).filter_by(public_id=customer_id).one_or_none()
    if customer is None:
        raise SystemExit("customer fixture missing")
    subscription = db.session.query(Subscription).filter_by(customer_email=customer.email).one_or_none()
    local_app = None
    if subscription and subscription.instance_id:
        local_app = db.session.query(CustomerApp).filter_by(instance_id=subscription.instance_id).one_or_none()
    return customer, subscription, local_app


def _emit_state(customer_id):
    customer, subscription, local_app = _fixture(customer_id)
    print(
        json.dumps(
            {
                "customer_id": customer.public_id if customer else None,
                "email": customer.email if customer else None,
                "signup_status": customer.signup_status if customer else None,
                "subscription_status": subscription.status if subscription else None,
                "paypal_subscription_id_present": bool(subscription and subscription.paypal_subscription_id),
                "subscription_next_billing_at": subscription.next_billing_at if subscription else None,
                "instance_id": subscription.instance_id if subscription else None,
                "technical_status": local_app.status if local_app else None,
                "commercial_status": local_app.commercial_status if local_app else None,
                "app_next_billing_at": local_app.next_billing_at if local_app else None,
            },
            sort_keys=True,
        )
    )


def setup():
    app = create_app()
    app.config["TESTING"] = True
    with app.app_context():
        existing = db.session.query(Customer).filter_by(email=EMAIL).one_or_none()
        if existing:
            raise SystemExit("refusing to overwrite an existing test customer")

    # Use Harbor's registration route so it generates the public customer ID.
    client = app.test_client()
    response = client.post(
        "/auth/register",
        data={
            "display_name": "RC6 Harbor authorization regression",
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
        if customer is None or not customer.public_id.startswith("hcus_"):
            raise SystemExit("Harbor registration did not create a generated hcus_ identity")
        customer.signup_status = "active"
        customer.is_active = True
        customer.reviewed_at = datetime.now(UTC)
        customer.reviewed_by = "issue-295-local-validation"
        db.session.commit()
        customer_id = customer.public_id

        # Use Harbor's packaged API client, not the system CLI, to provision.
        provision = provision_app(
            APP_SLUG,
            TIER,
            customer_id,
            "rc6-issue295-" + customer_id,
        )
        instance_id = provision.get("instance_id", "")
        operation_id = provision.get("operation_id", "")
        if not instance_id or not operation_id:
            raise SystemExit("Harbor API provision response lacks instance/operation IDs")

        status = "queued"
        deadline = time.monotonic() + 600
        while time.monotonic() < deadline:
            operation = get_operation(operation_id, instance_id=instance_id, customer_id=customer_id)
            status = operation.get("status", "")
            if status in {"succeeded", "failed", "cancelled"}:
                break
            time.sleep(2)
        if status != "succeeded":
            raise SystemExit(f"Harbor API provision operation ended as {status!r}")

        get_status = "PASS"
        try:
            remote = get_customer_app(instance_id, customer_id)
            if remote.get("id") != instance_id:
                raise SystemExit("Harbor customer-scoped instance read returned a different instance")
        except AdmiralAPIError as exc:
            get_status = "FAIL: " + str(exc)

        prepaid_end = (datetime.now(UTC).date() + timedelta(days=7)).isoformat()
        subscription = Subscription(
            customer_email=customer.email,
            app_slug=APP_SLUG,
            status="cancelled",
            instance_id=instance_id,
            paypal_subscription_id=None,
            tier_name=TIER,
            total_cents=500,
            next_billing_at=prepaid_end,
        )
        db.session.add(subscription)
        db.session.flush()
        db.session.add(
            CustomerApp(
                subscription_id=subscription.id,
                customer_email=customer.email,
                instance_id=instance_id,
                app_slug=APP_SLUG,
                domain="issue295-harbor-flow.example.invalid",
                status="running",
                commercial_status="cancelled",
                next_billing_at=prepaid_end,
            )
        )
        db.session.commit()
        print(
            json.dumps(
                {
                    "registration_status": response.status_code,
                    "customer_id": customer_id,
                    "customer_id_generated_by_harbor": True,
                    "instance_id": instance_id,
                    "provision_operation_id": operation_id,
                    "provision_status": status,
                    "customer_scoped_read": get_status,
                    "paypal_subscription_id_present": False,
                    "prepaid_end": prepaid_end,
                },
                sort_keys=True,
            )
        )


def expire(customer_id):
    app = create_app()
    with app.app_context():
        _, subscription, local_app = _fixture(customer_id)
        if not subscription or not local_app:
            raise SystemExit("test subscription fixture missing")
        expired = (datetime.now(UTC).date() - timedelta(days=1)).isoformat()
        subscription.next_billing_at = expired
        local_app.next_billing_at = expired
        db.session.commit()
        _emit_state(customer_id)


def cleanup(customer_id):
    app = create_app()
    with app.app_context():
        customer, subscription, local_app = _fixture(customer_id)
        if local_app:
            db.session.delete(local_app)
        if subscription:
            db.session.delete(subscription)
        if customer:
            db.session.delete(customer)
        db.session.commit()
        print(json.dumps({"cleanup": "complete", "customer_id": customer_id}, sort_keys=True))


if __name__ == "__main__":
    if len(sys.argv) == 1:
        setup()
    elif len(sys.argv) == 3 and sys.argv[1] == "expire":
        expire(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "inspect":
        app = create_app()
        with app.app_context():
            _emit_state(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "cleanup":
        cleanup(sys.argv[2])
    else:
        raise SystemExit("usage: issue-295-harbor-flow.py [expire|inspect|cleanup CUSTOMER_ID]")
