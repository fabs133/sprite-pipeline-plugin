# Top-Up Implementation Guide

## Current Status: NOT IMPLEMENTED

Top-up (one-time purchase) products are **not yet configured** in the backend.

---

## What Needs to be Done

### 1. Get Stripe Price IDs for Top-Up Products

From your Stripe dashboard, get the Price IDs for your top-up products:
- 50 pictures (one-time)
- 100 pictures (one-time)
- 250 pictures (one-time)

These should look like: `price_XXXXXXXXXXXXX`

### 2. Update Backend Configuration

**File:** `app/config.py`

Add after `stripe_tier2_price_id`:
```python
    stripe_topup_50_price_id: str = ""
    stripe_topup_100_price_id: str = ""
    stripe_topup_250_price_id: str = ""
```

Add after `tier2_units`:
```python
    topup_50_units: int = 50
    topup_100_units: int = 100
    topup_250_units: int = 250
```

### 3. Update Environment Variables

**File:** `.env` on server

Add these lines:
```env
SPRITE_STRIPE_TOPUP_50_PRICE_ID=price_XXXXX
SPRITE_STRIPE_TOPUP_100_PRICE_ID=price_XXXXX
SPRITE_STRIPE_TOPUP_250_PRICE_ID=price_XXXXX
```

### 4. Update Billing Routes

**File:** `app/routes/billing.py`

**Add top-up price ID mapping:**
```python
def _get_price_id(plan: str) -> str:
    if plan == "tier1":
        return settings.stripe_tier1_price_id
    elif plan == "tier2":
        return settings.stripe_tier2_price_id
    elif plan == "topup_50":
        return settings.stripe_topup_50_price_id
    elif plan == "topup_100":
        return settings.stripe_topup_100_price_id
    elif plan == "topup_250":
        return settings.stripe_topup_250_price_id
    raise ValueError(f"Unknown plan: {plan}")
```

**Add top-up units mapping:**
```python
def _get_units(plan: str) -> int:
    """Get units for a plan."""
    if plan == "tier1":
        return settings.tier1_units
    elif plan == "tier2":
        return settings.tier2_units
    elif plan == "topup_50":
        return settings.topup_50_units
    elif plan == "topup_100":
        return settings.topup_100_units
    elif plan == "topup_250":
        return settings.topup_250_units
    return 0
```

**Update checkout endpoint to support one-time payments:**
```python
@router.post("/checkout")
async def create_checkout(
    plan: str = "tier1",
    return_url: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a Stripe Checkout Session for subscription or one-time purchase."""

    try:
        price_id = _get_price_id(plan)
    except ValueError:
        raise HTTPException(status_code=400, detail={"error": "invalid_plan", "message": f"Unknown plan: {plan}"})

    # Create or reuse Stripe customer
    if not user.stripe_customer_id:
        customer = stripe.Customer.create(email=user.email)
        user.stripe_customer_id = customer.id
        await db.flush()

    base_url = _validate_return_url(return_url)

    # Determine mode: subscription for tiers, payment for top-ups
    is_topup = plan.startswith("topup_")
    mode = "payment" if is_topup else "subscription"

    session = stripe.checkout.Session.create(
        customer=user.stripe_customer_id,
        mode=mode,
        line_items=[{"price": price_id, "quantity": 1}],
        success_url=f"{base_url}?checkout=success",
        cancel_url=f"{base_url}?checkout=cancel",
        metadata={"user_id": str(user.id), "plan": plan},
    )

    await db.commit()
    return {"checkout_url": session.url}
```

**Handle one-time payment webhook:**
```python
    elif event_type == "checkout.session.completed":
        session = event["data"]["object"]
        user_id = session.get("metadata", {}).get("user_id")
        plan = session.get("metadata", {}).get("plan", "tier1")
        subscription_id = session.get("subscription")
        payment_intent = session.get("payment_intent")

        if user_id:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if user:
                # Check if it's a one-time top-up or subscription
                is_topup = plan.startswith("topup_")

                if is_topup:
                    # One-time purchase: add credits immediately
                    units = _get_units(plan)
                    from ..services.quota_service import add_quota
                    await add_quota(db, user.id, units, f"topup_{plan}")
                    _log.info(
                        "topup_processed",
                        user_id=str(user.id),
                        plan=plan,
                        units=units,
                        payment_intent=payment_intent
                    )
                else:
                    # Subscription: set up user plan
                    user.plan_id = plan
                    user.plan_status = "active"
                    user.stripe_subscription_id = subscription_id
```

### 5. Create Frontend Top-Up Component

**File:** `src/components/react/TopUpButton.tsx`

```typescript
import { useState } from 'react';
import { createCheckout } from '../../lib/api';

interface TopUpButtonProps {
  plan: 'topup_50' | 'topup_100' | 'topup_250';
  units: number;
  price: number;
  label?: string;
  className?: string;
}

export default function TopUpButton({ plan, units, price, label, className = '' }: TopUpButtonProps) {
  const [loading, setLoading] = useState(false);

  const handleCheckout = async () => {
    setLoading(true);
    try {
      const returnUrl = `${window.location.origin}/dashboard`;
      const { checkout_url } = await createCheckout(plan, returnUrl);
      window.location.href = checkout_url;
    } catch (error) {
      console.error('Top-up checkout error:', error);
      alert('Failed to start checkout. Please try again or contact support.');
      setLoading(false);
    }
  };

  return (
    <button
      onClick={handleCheckout}
      disabled={loading}
      className={className}
    >
      {loading ? 'Loading...' : (label || `Buy ${units} pictures for $${price}`)}
    </button>
  );
}
```

### 6. Add Top-Up Section to Dashboard

**File:** `src/components/react/DashboardOverview.tsx`

Add after the stats cards:
```tsx
{/* Top-up credits */}
<div className="bg-white rounded-xl border border-slate-200 p-6 mb-8">
  <h2 className="text-lg font-semibold text-slate-900 mb-4">Need More Pictures?</h2>
  <p className="text-sm text-slate-600 mb-4">
    Purchase additional pictures without changing your plan.
  </p>

  <div className="grid grid-cols-3 gap-4">
    <TopUpButton
      plan="topup_50"
      units={50}
      price={5}
      className="px-4 py-3 bg-slate-100 hover:bg-slate-200 rounded-lg text-sm font-medium text-slate-700 transition-colors"
    />
    <TopUpButton
      plan="topup_100"
      units={100}
      price={9}
      className="px-4 py-3 bg-brand-100 hover:bg-brand-200 rounded-lg text-sm font-medium text-brand-700 transition-colors"
    />
    <TopUpButton
      plan="topup_250"
      units={250}
      price={20}
      className="px-4 py-3 bg-slate-100 hover:bg-slate-200 rounded-lg text-sm font-medium text-slate-700 transition-colors"
    />
  </div>
</div>
```

---

## Implementation Steps

1. **Get Stripe Price IDs** from your Stripe dashboard for top-up products
2. **SSH into server:**
   ```bash
   ssh droid@192.168.178.30
   cd /home/droid/.ssh/sprite-pipeline-backend
   ```

3. **Update config.py** with the additions above

4. **Update .env** with your top-up Price IDs

5. **Update app/routes/billing.py** with the new code

6. **Restart backend:**
   ```bash
   docker compose restart backend
   ```

7. **Update frontend** with TopUpButton component and dashboard integration

8. **Deploy frontend** (Vercel auto-deploys on push)

9. **Test** with Stripe test mode first

---

## Testing

### Test Flow:
1. Login to dashboard
2. Click a top-up button (e.g., "Buy 50 pictures for $5")
3. Redirect to Stripe checkout
4. Use test card: `4242 4242 4242 4242`
5. Complete payment
6. Redirect back to dashboard
7. Verify credits added to quota
8. Check backend logs for "topup_processed"

### Monitor:
```bash
docker compose logs backend | grep "topup_processed"
```

---

## Pricing Recommendations

Based on subscription pricing:
- Tier 1: $9/month for 100 pictures = $0.09/picture
- Tier 2: $29/month for 500 pictures = $0.058/picture

**Top-up pricing (one-time, no subscription):**
- 50 pictures: **$5** ($0.10/picture) - Slightly more expensive than subscription
- 100 pictures: **$9** ($0.09/picture) - Same as Tier 1 monthly
- 250 pictures: **$20** ($0.08/picture) - Better value for larger purchase

This encourages subscriptions while still offering flexibility.

---

## Current Status

- [x] Subscriptions working (Tier 1, Tier 2)
- [ ] Top-ups NOT implemented yet
- [ ] Need Stripe Price IDs
- [ ] Need backend code changes
- [ ] Need frontend components

**Estimated implementation time:** 1-2 hours

---

## Next Steps

1. Share your Stripe top-up Price IDs
2. I'll implement the backend changes
3. Create frontend components
4. Deploy and test
5. Launch top-up feature

Would you like me to implement this now if you provide the Stripe Price IDs?
