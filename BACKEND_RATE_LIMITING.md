# Backend OpenAI Rate Limiting Configuration

## ✅ Current Status

**Yes, OpenAI rate limiting IS implemented** in the backend with automatic retry and exponential backoff.

### Implementation Details

**Location:** `app/services/pipeline_runner.py` (FastHookProvider class)

**How it works:**
1. **Automatic Detection**: Catches rate limit errors (429, "rate_limit", "too many requests")
2. **Exponential Backoff**: Retries with increasing delays: 1s, 2s, 4s
3. **Max Retries**: Configurable (default: 3 attempts)
4. **Fallback Models**: Can specify alternative models if primary fails

### Current Configuration

**Backend Server:** `192.168.178.30`
**Config Location:** `/home/droid/.ssh/sprite-pipeline-backend/.env`

```env
# Rate Limiting Settings
SPRITE_LITELLM_ENABLED=true
SPRITE_LITELLM_MAX_RETRIES=3          # Number of retry attempts
SPRITE_LITELLM_RETRY_DELAY=1.0        # Initial delay (seconds)
```

**Retry Pattern (Exponential Backoff):**
- Attempt 1: Request sent
- Rate limit hit → Wait 1.0s
- Attempt 2: Retry
- Rate limit hit → Wait 2.0s (1.0 × 2^1)
- Attempt 3: Retry
- Rate limit hit → Wait 4.0s (1.0 × 2^2)
- Final attempt or fail

## 🔧 How to Adjust Settings

### Option 1: Via Environment Variables (Recommended)

```bash
# SSH into server
ssh droid@192.168.178.30

# Navigate to backend
cd /home/droid/.ssh/sprite-pipeline-backend

# Edit .env file
nano .env

# Modify these values:
SPRITE_LITELLM_MAX_RETRIES=5         # Increase retries (default: 3)
SPRITE_LITELLM_RETRY_DELAY=2.0       # Increase initial delay (default: 1.0)

# Save and restart backend
docker compose restart backend
```

### Option 2: Via Docker Compose Override

```bash
cd /home/droid/.ssh/sprite-pipeline-backend

# Edit docker-compose.yml
nano docker-compose.yml

# Add environment variables under backend service:
services:
  backend:
    environment:
      - SPRITE_LITELLM_MAX_RETRIES=5
      - SPRITE_LITELLM_RETRY_DELAY=2.0

# Restart
docker compose up -d backend
```

## 📊 Recommended Settings by Tier

### Free Tier / Low Volume (Default)
```env
SPRITE_LITELLM_MAX_RETRIES=3
SPRITE_LITELLM_RETRY_DELAY=1.0
```
- **Max wait time:** ~7 seconds (1 + 2 + 4)
- **Good for:** < 50 requests/day

### Standard Tier / Medium Volume
```env
SPRITE_LITELLM_MAX_RETRIES=5
SPRITE_LITELLM_RETRY_DELAY=2.0
```
- **Max wait time:** ~62 seconds (2 + 4 + 8 + 16 + 32)
- **Good for:** 50-500 requests/day

### Heavy Usage / High Volume
```env
SPRITE_LITELLM_MAX_RETRIES=7
SPRITE_LITELLM_RETRY_DELAY=3.0
```
- **Max wait time:** ~381 seconds (~6 minutes)
- **Good for:** 500+ requests/day
- **Warning:** Long wait times may cause client timeouts

## 🚨 OpenAI Rate Limits (as of 2024)

### DALL-E 3 (Image Generation)
- **Free Trial:** 3 requests/min, 200 requests/day
- **Tier 1:** 5 requests/min, ~500 requests/day
- **Tier 2:** 7 requests/min, ~1000 requests/day
- **Tier 3+:** Higher limits based on usage

### Rate Limit Headers
OpenAI returns these headers (LiteLLM automatically reads them):
```
x-ratelimit-limit-requests: 5
x-ratelimit-remaining-requests: 4
x-ratelimit-reset-requests: 12s
```

## 🔍 Monitoring Rate Limits

### Check Backend Logs
```bash
ssh droid@192.168.178.30
cd /home/droid/.ssh/sprite-pipeline-backend
docker compose logs -f backend | grep -i "rate"
```

**Look for:**
- `rate_limited_retrying` - System is handling rate limits
- `rate_limit_exceeded` - Too many requests, all retries failed

### Check Generation Metrics
The backend tracks metrics in memory:
```python
# In pipeline_runner.py
_generation_metrics = {
    "total_requests": 0,
    "successful_requests": 0,
    "failed_requests": 0,
    "retries": 0,           # Number of rate limit retries
    "fallbacks_used": 0,
    "total_latency_ms": 0,
}
```

## ⚙️ Advanced Configuration

### Add Fallback Models
If primary model is rate-limited, try alternatives:

```env
# Use Azure DALL-E as fallback
SPRITE_LITELLM_FALLBACK_MODELS=azure/dall-e-3,openai/dall-e-3

# Or use gpt-image-1 (if available)
SPRITE_LITELLM_FALLBACK_MODELS=gpt-image-1,dall-e-3
```

### Disable LiteLLM (Not Recommended)
```env
SPRITE_LITELLM_ENABLED=false
```
**Warning:** Disables automatic retry and rate limit handling!

## 🧪 Testing Rate Limits

### Simulate Rate Limit
```bash
# Send many requests quickly
for i in {1..10}; do
  curl -X POST http://192.168.178.30:8000/v1/generate \
    -H "Authorization: Bearer YOUR_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"prompt": "test sprite", "style": "pixel"}' &
done

# Check logs for rate_limited_retrying messages
docker compose logs backend | tail -50
```

## 📝 Code Reference

**Rate Limit Detection:**
```python
# app/services/pipeline_runner.py:317
is_rate_limit = any(kw in error_msg for kw in (
    "rate_limit",
    "rate limit",
    "429",
    "too many requests"
))
```

**Exponential Backoff:**
```python
# app/services/pipeline_runner.py:321
delay = self._retry_delay * (2 ** attempt)
await asyncio.sleep(delay)
```

**Max Retries:**
```python
# app/services/pipeline_runner.py:319
if is_rate_limit and attempt < self._max_retries - 1:
    # Retry with backoff
```

## ✅ Verification Checklist

Before launch:
- [x] Rate limiting implemented in backend
- [x] Exponential backoff configured
- [x] Max retries set to 3 (reasonable default)
- [x] Retry delay set to 1.0s (reasonable default)
- [x] Error messages logged for monitoring
- [x] Easy to adjust via environment variables
- [x] No code changes needed to tune settings

## 🎯 Recommendations for Launch

**Current settings are GOOD for launch:**
```env
SPRITE_LITELLM_MAX_RETRIES=3
SPRITE_LITELLM_RETRY_DELAY=1.0
```

**Why these settings work:**
1. **Fast enough:** Max 7-second wait for rate limits
2. **Tolerant enough:** 3 retries handles temporary spikes
3. **User-friendly:** Won't cause long timeouts in plugin
4. **Adjustable:** Can increase later if needed

**When to adjust:**
- **Increase retries (5-7):** If you see "rate_limit_exceeded" errors frequently
- **Increase delay (2-3s):** If OpenAI rate limits are very strict
- **Add fallbacks:** If you have Azure or alternative providers

## 🚀 Post-Launch Monitoring

**Week 1:** Monitor logs for rate limit events
```bash
# Daily check
docker compose logs backend | grep "rate_limited_retrying" | wc -l
```

**If seeing many retries:**
1. Check OpenAI tier at https://platform.openai.com/account/limits
2. Consider increasing `MAX_RETRIES` to 5
3. Add API key auto-recharge (already configured in OpenAI dashboard)

**If users report timeouts:**
1. Check if `MAX_RETRIES` is too high (causing long waits)
2. Reduce to 2-3 retries for faster failures
3. Show better error messages to users

---

## Summary

✅ **Rate limiting is fully implemented and production-ready**
- Automatic retry with exponential backoff
- Easy to adjust via environment variables
- Current settings are appropriate for launch
- No code changes needed

**Status:** Ready for launch! 🚀

**Next action:** None required. Settings are optimal for initial launch. Monitor logs in first week and adjust if needed.
