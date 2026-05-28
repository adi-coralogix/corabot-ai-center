/** Call after init to set user session info (e.g. after login) */
export function setCoralogixUserContext(user: {
	userId: string;
	userName?: string;
	userEmail?: string;
}) {
	if (typeof window !== 'undefined') {
		import('@coralogix/browser').then(({ CoralogixRum }) => {
			CoralogixRum.setUserContext({
				user_id: user.userId,
				user_name: user.userName ?? '',
				user_email: user.userEmail
			});
		});
	}
}

/** Must match `@coralogix/browser` `CoralogixDomainsApiUrlMap` keys used in this app. */
export type CoralogixRumDomain = 'US2' | 'EU1';

/** Cached init args so startNewCoralogixSession() can re-init with the same config. */
let _lastInitKey: string | null = null;
let _lastInitDomain: CoralogixRumDomain = 'US2';

/**
 * Tear down the current Coralogix RUM session and start a fresh one.
 * The next browser events (and the `traceparent` header on outbound fetches) will belong
 * to a new session_id — visible in RUM + linked to the new AI Center conversation via the
 * gen_ai.conversation.id propagated in the chat request body.
 */
export async function startNewCoralogixSession(): Promise<string | undefined> {
	if (typeof window === 'undefined' || !_lastInitKey) return undefined;
	try {
		const { CoralogixRum } = await import('@coralogix/browser');
		CoralogixRum.shutdown();
		// Re-init with the same key/domain so the SDK mints a new session_id.
		await initCoralogixRum(_lastInitKey, _lastInitDomain);
		return CoralogixRum.getSessionId();
	} catch (err) {
		console.warn('[Coralogix RUM] startNewCoralogixSession failed', err);
		return undefined;
	}
}

export async function initCoralogixRum(
	publicKey: string,
	coralogixDomain: CoralogixRumDomain = 'US2'
) {
	if (typeof window === 'undefined') return;
	const key = publicKey?.trim() ?? '';
	if (!key) {
		console.warn(
			'[Coralogix RUM] No public key — set VITE_CORALOGIX_RUM_KEY or PUBLIC_CORALOGIX_RUM_KEY in .env (browser RUM disabled).'
		);
		return;
	}
	if (key.startsWith('your_')) {
		console.warn(
			'[Coralogix RUM] Key is still a template (starts with your_) — use the real RUM public key from Coralogix; browser RUM not initialized.'
		);
		return;
	}
	_lastInitKey = key;
	_lastInitDomain = coralogixDomain;
	// Harness traffic is fully isolated: separate `application` + `environment` so dashboards
	// filtered on `application=coralogix-arcade` see only real users.
	const isSynthetic = /test_harness/i.test(navigator.userAgent || '');
	const application = isSynthetic ? 'coralogix-arcade-synthetic' : 'coralogix-arcade';
	const environment = isSynthetic
		? 'synthetic'
		: import.meta.env.DEV
			? 'development'
			: 'production';
	const { CoralogixRum } = await import('@coralogix/browser');
	CoralogixRum.init({
		public_key: key,
		environment,
		application,
		version: '1.0.0',
		coralogixDomain,
		/** Set user session info for RUM. Call setCoralogixUserContext() after login to update. */
		user_context: {
			user_id: isSynthetic ? 'rum-harness' : '',
			user_name: isSynthetic ? 'RUM Harness' : '',
			user_email: undefined
		},
		sessionRecordingConfig: {
			enable: true,
			autoStartSessionRecording: true,
			recordConsoleEvents: true,
			sessionRecordingSampleRate: 100
		},
		// In-cluster harness: EU1 ingest can still fail if blocked; log for Coralogix / Network debugging
		traceParentInHeader: {
			enabled: true,
			options: {
				propagateTraceHeaderCorsUrls: [
					new RegExp('http://localhost:8000.*'),
					new RegExp('http://127\\.0\\.0\\.1:8000.*'),
					// Same-origin /api on cluster Ingress or ClusterIP fronts
					new RegExp('https?:\\/\\/[^/]+\\/api/.*'),
				],
			},
		},
	});
}
