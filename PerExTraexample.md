# PRD — Personal Expense Tracker

## 1. Product Context

### Problem

Users often record expenses inconsistently, making it difficult
to understand where their money goes and whether they are
staying within their budget.

### Goal

Help users record, categorize, and review their expenses so
they can understand their spending patterns and monitor
their monthly budget.

### Target Users

- Individuals who want to track personal expenses.
- Users who want to monitor spending against a monthly budget.

### Value

The application provides a simple way to record expenses
and understand spending patterns.

---

## 2. Scope

### In Scope

- Record expenses
- Categorize expenses
- View expense history
- Set monthly budgets
- View spending summaries
- Compare spending with budget

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

**Expected Result**

The expense is recorded and included in the user's
expense history and spending information.

### UC-02 — View Expense History

User views previously recorded expenses
and can filter them by date or category.

**Expected Result**

The user can find and review relevant expenses.

### UC-03 — Set Monthly Budget

User defines a spending limit for a month.

**Expected Result**

The selected month's budget is reflected
in the spending information.

### UC-04 — View Spending Summary

User selects a month to review spending.

**Expected Result**

The user can see:

- Total spending
- Spending by category
- Monthly budget
- Remaining budget when a budget is set

---

## 4. Product Rules

- An expense must have an amount, category, and date.
- The expense amount must be greater than zero.
- An expense belongs to the user who records it.
- A monthly budget applies to one user and one month.
- Spending is calculated from expenses recorded for the selected month.
- If no budget is set, spending can still be viewed.

---

## 5. Requirements

### FR-01 — Create Expense

The system must allow users to create an expense.

The system must reject an expense when:
- The amount is zero or negative.
- The category is missing.
- The date is invalid.

### FR-02 — Set Monthly Budget

The system must allow users to set a budget for a selected month.

When a budget already exists for that month,
setting a new budget replaces the previous budget.

### FR-03 — View Spending Summary

The system must allow users to select a month
and view spending information for that month.

The summary must show:
- Total spending
- Spending by category
- Budget when available
- Remaining budget when a budget is available

---

## 6. Acceptance Criteria

### Record Expense

- A valid expense can be recorded.
- An invalid expense cannot be recorded.
- A recorded expense appears in the user's expense history.

### Set Monthly Budget

- A user can set a budget for a month.
- Setting a budget again for the same month updates that budget.

### View Spending Summary

- The selected month's expenses are included in the summary.
- Spending is grouped by category.
- Budget information is shown when a budget exists.
- Spending remains viewable when no budget exists.