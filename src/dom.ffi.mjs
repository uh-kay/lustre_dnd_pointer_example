/**
 *
 * @param {Element} element
 * @returns {DOMRect}
 */
export function getBoundingClientRect(element) {
  return element.getBoundingClientRect();
}

/**
 *
 * @param {Element} element
 * @param {Number} pointerId
 * @returns {void}
 */
export function releasePointerCapture(element, pointerId) {
  if (element.hasPointerCapture?.(pointerId)) {
    element.releasePointerCapture(pointerId);
  }
}
