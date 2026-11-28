/*
 *  pamac-vala
 *
 *  Copyright (C) 2026 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

namespace Pamac {
	// the steps of a transaction reported by Transaction.emit_transaction_progress
	public enum TransactionStep {
		// current and total are bytes of the downloaded packages
		DOWNLOADING,
		// current and total are packages installed, upgraded or removed
		PROCESSING,
		// current and total are hooks
		RUNNING_HOOKS,
		// current and total are AUR packages to build
		BUILDING
	}

	// receives the progress of an operation.
	// The methods are called from worker threads (alpm callbacks)
	// or from the main thread: an implementation must be thread-safe
	// and move the calls to the thread it needs itself
	internal interface TransactionSink : Object {
		public abstract void emit_action (string action);
		public abstract void emit_action_progress (string action, string status, double progress);
		public abstract void emit_download_progress (string action, string status, double progress);
		public abstract void emit_hook_progress (string action, string details, string status, double progress);
		// step is a TransactionStep, an uint to be sent with D-Bus
		public abstract void emit_transaction_progress (uint step, uint64 current, uint64 total);
		public abstract void emit_script_output (string message);
		public abstract void emit_warning (string message);
		public abstract void emit_error (string message, GenericArray<string> details);
		public abstract void important_details_outpout (bool must_show);
		public abstract void start_downloading ();
		public abstract void stop_downloading ();
		public abstract void start_waiting ();
		public abstract void stop_waiting ();
		// blocks the calling worker thread until answered,
		// returns the index of the chosen provider
		public abstract int choose_provider (string depend, GenericArray<string> providers);
	}

	// drops the progress and chooses the first provider
	internal class NullSink : Object, TransactionSink {
		public void emit_action (string action) {}
		public void emit_action_progress (string action, string status, double progress) {}
		public void emit_download_progress (string action, string status, double progress) {}
		public void emit_hook_progress (string action, string details, string status, double progress) {}
		public void emit_transaction_progress (uint step, uint64 current, uint64 total) {}
		public void emit_script_output (string message) {}
		public void emit_warning (string message) {}
		public void emit_error (string message, GenericArray<string> details) {}
		public void important_details_outpout (bool must_show) {}
		public void start_downloading () {}
		public void stop_downloading () {}
		public void start_waiting () {}
		public void stop_waiting () {}
		public int choose_provider (string depend, GenericArray<string> providers) {
			return 0;
		}
	}
}
