/**
 * Restore the last used model on startup.
 *
 * Saves provider/modelId to ~/.pi/agent/last-model.json on every model switch
 * (/model picker or Ctrl+P cycle) and applies it back when a new pi session
 * starts. Resuming an old session is left to pi itself (its own model is
 * replayed), and "restore" events never overwrite the saved selection.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";

const stateFile = () => join(getAgentDir(), "last-model.json");

export default function (pi: ExtensionAPI) {
	pi.on("model_select", (event) => {
		if (event.source === "restore") return;
		writeFileSync(stateFile(), JSON.stringify({ provider: event.model.provider, id: event.model.id }));
	});

	pi.on("session_start", async (event, ctx: ExtensionContext) => {
		if (event.reason !== "startup") return;
		const saved = loadState();
		if (!saved) return;
		const model = ctx.modelRegistry.find(saved.provider, saved.id);
		if (!model) return; // model no longer registered, keep the default
		const ok = await pi.setModel(model);
		if (!ok) ctx.ui.notify(`Last model ${saved.provider}/${saved.id} unavailable (no auth)`, "warning");
	});
}

function loadState(): { provider: string; id: string } | undefined {
	const file = stateFile();
	if (!existsSync(file)) return undefined;
	try {
		const parsed = JSON.parse(readFileSync(file, "utf8"));
		return typeof parsed?.provider === "string" && typeof parsed?.id === "string" ? parsed : undefined;
	} catch {
		return undefined;
	}
}