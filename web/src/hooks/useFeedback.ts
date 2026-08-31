import { useContext } from 'solid-js';

import { FeedbackContext } from '#ui/context/FeedbackContext';

/** Global toast + confirm host; see `FeedbackProvider`. */
export function useFeedback() {
  return useContext(FeedbackContext);
}
