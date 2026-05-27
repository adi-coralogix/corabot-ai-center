import type { LayoutServerLoad } from './$types';
import type { CoralogixRumDomain } from '$lib/coralogix-rum';

/** Kubernetes / Docker: PUBLIC_CORALOGIX_RUM_KEY + PUBLIC_CORALOGIX_DOMAIN (US2 | EU1). Local dev uses VITE_* / build defaults. */
export const load: LayoutServerLoad = async () => {
	const rumPublicKey = process.env.PUBLIC_CORALOGIX_RUM_KEY?.trim() ?? '';
	const rawDomain = process.env.PUBLIC_CORALOGIX_DOMAIN?.trim().toUpperCase() ?? '';
	const rumCoralogixDomain: CoralogixRumDomain =
		rawDomain === 'EU1' ? 'EU1' : 'US2';
	return { rumPublicKey, rumCoralogixDomain };
};
