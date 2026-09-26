export {};

declare global {
  interface Window {
    keepitDesktop?: {
      isDesktop: boolean;
      isCaptureWindow: boolean;
      closeCapture: () => void;
      captureSaved: () => void;
      syncReminders: (reminders: Array<{ id: string; title: string; remindAt: string }>) => void;
      onImportItem: (callback: (item: unknown) => void) => () => void;
      onOpenReminder: (callback: (itemId: string) => void) => () => void;
    };
  }
}
