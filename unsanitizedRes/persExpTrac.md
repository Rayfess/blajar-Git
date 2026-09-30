# PRD — Personal Expense Tracker

## 1. Product Context

### Problem

Users often record expenses inconsistently, making it difficult
to understand where their money goes and whether they are
staying within their budget.

### Goal

Help users record, categorize, and review their expenses so
they can understand their spending patterns.

### Target Users

- Individuals who want to track personal expenses.
- Users who want to monitor spending against a monthly budget.

### Value

The application provides a simple way to record expenses and
turn them into understandable spending information.

---

## 2. Scope

### In Scope

- Record expenses
- Categorize expenses
- View expense history
- Set monthly budgets
- View spending summaries
- View spending against budget

### Out of Scope

- Bank account integration
- Automatic transaction import
- Investment management
- Tax calculation

---

## 3. Core Use Cases

### UC-01 — Record Expense

User records an expense with:

- Amount
- Category
- Date
- Description

### UC-02 — View Expense History

User views previously recorded expenses
and can filter them by date or category.

### UC-03 — Set Monthly Budget

User defines a spending limit for a month.

### UC-04 — View Spending Summary

User views total spending grouped by category
and compares it with the monthly budget.

---

## 4. Functional Requirements

### FR-01 — Create Expense

**Input**

- Amount
- Category
- Date
- Description

**Process**

1. Validate the submitted data.
2. Create the expense record.
3. Associate the expense with the current user.
4. Update the relevant spending summary.

**Output**

The expense appears in the user's expense history.

**Rules**

- Amount must be greater than zero.
- Category must be selected.
- Date must be valid.

---

### FR-02 — Set Monthly Budget

**Input**

- Month
- Budget amount

**Process**

1. Validate the amount.
2. Create or update the budget for the selected month.

**Output**

The budget becomes visible in the user's
monthly spending summary.

---

### FR-03 — View Spending Summary

**Input**

- Selected month

**Process**

1. Retrieve expenses for the selected month.
2. Group expenses by category.
3. Calculate total spending.
4. Compare spending with the monthly budget.

**Output**

The system displays:

- Total spending
- Spending by category
- Budget
- Remaining budget