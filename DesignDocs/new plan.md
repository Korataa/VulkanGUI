Here’s the content for your plan. Save this as PLAN.md in your project root:

---

## Plan: UIManager Input Handling and Event Dispatch

**Goal:**  
Connect the input provider to the UI system so that UI elements (e.g., buttons) can respond to mouse input (hover, click).

---

**Steps**

1. Extend UIManager with Input Handling
   - Add a method to UIManager, e.g., handleInput(input: InputProvider).
   - This method will:
     - Retrieve the current mouse position and button state from the input provider.
     - Perform hit-testing on the UI tree (starting from the root element).
     - Track hover state and detect mouse button transitions (pressed/released).
     - If a button is clicked, invoke its tapHandler.

2. Hit Testing Logic
   - Implement a recursive hit-test function in Element to find the topmost element under the mouse.
   - Only elements with a tapHandler (e.g., buttons) should respond to clicks.

3. Main Loop Integration
   - In the main loop, after inputProvider.update() and before uiManager.update(), call uiManager.handleInput(input: inputProvider).
   - This ensures input is processed with the latest state before the UI is rebuilt/rendered.

4. Verification
   - Add a test button to the UI with a print/log action.
   - Run the app and verify that clicking the button triggers the action.
   - Confirm that hover and click states are correctly detected and dispatched.

---

**Relevant files**
- UIManager.swift — Add input handling method
- Element.swift — Add hit-testing and event dispatch logic
- main.swift — Integrate input handling in the main loop

---

**Decisions**
- Only mouse input is required for initial implementation (keyboard/focus can be added later).
- Hit-testing uses element bounds.
- Event dispatch is immediate (no event queue).

---

**Further Considerations**
- For more complex UI, consider event bubbling/capturing in the future.
- Keyboard navigation and accessibility can be layered on later.

---

You can copy and paste this into a new PLAN.md file in your project root. If you want me to walk you through creating the file in your editor, just ask!