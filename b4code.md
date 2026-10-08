# WHY, WHAT, HOW, QUALITY (2WHQ)
Before start to code we must implement our ideas to this concepts for better understanding on project that we do

## WHY - WHY we must create this

**What Problem do we want to solve, WHY does this solution we provide helps** 

*This is BRD(Business Requirement Document) domain*

Output :
```
Problem
Goal
Scope
Stakeholder
Solutions
```

## WHAT - WHAT does this project do

**WHAT does the project do for achieving the setted goals**

*This is PRD(Product Requirement Document) domain*

Output:
```
User
Use Case
Feature
Requirement
Acceptance Criteria
```

## HOW - HOW does the project works

explains on three main :
```
FLOW
How is the process work

DATA
How is the data work to this

ARCHITECTURE
How is the component being divided and communicate one to another
```

## QUALITY - How good the QUALITY to be work

**At what standarts this project should match**

Output :
```
Security
Performance
Reliability
Scalability
Maintainability
Cost
Observability
```

example :
*Login time must respond before 500ms and safe from brute force*


## Risk Management Plan
A Risk Management Plan describes how a project will identify, evaluate, handle, and monitor risks.


It answers:

> What can go wrong, how serious is it, and what will we do about it?


| Risk                | Impact | Mitigation          |
|---------------------|--------|---------------------|
| Database Failure    | High   | Backup and Recovery |
| Requirement Changes | High   | Change Control      |
| Developer Unavaible | Medium | Knowledge Sharing   |
| Security Vulnerable | High   | Security Testing    |


The basic process is:

**Identify → Analyze → Respond → Monitor**


**The Risk Management Plan is about managing project and product risks.**



## Risk Management Framework
RMF (Risk Management Framework) is a structured framework for managing risk, especially security risk.


It answers:

> How do we systematically manage and control security risks throughout the system lifecycle?


For example, a security-oriented RMF process may include:

**Categorize → Select → Implement → Assess → Authorize → Monitor**


For a system that stores sensitive user data, we might ask:
- What data needs protection?
- What threats exist?
- What security controls are needed?
- Are the controls working?
- Is the system safe enough to operate?
- How will we continue monitoring it?


### Diffrence between RMP and RMF

**Risk Management Plan**

> A plan for managing risks in a specific project.


**Risk Management Framework**

> A framework or process for systematically managing risk.

**Risk Management Framework = Framework / Methodology**

**Risk Management Plan = Project-specific plan**


## Software Development Plan
SDP (Software Development Plan) describes how the software project will be developed and managed.


It answers:

> How are we going to develop this software?


An SDP may define:
- Development methodology
- Team responsibilities
- Development tools
- Coding practices
- Testing process
- Review process
- Release process
- Development environment
- Configuration management
- Project milestones


For example:
> We use Git for version control.
Developers use feature branches.
Changes require code review.
Automated tests run before merging.
Releases are performed through CI/CD.


**So, SDP focuses on the development process, not the detailed behavior of the application.**


## Software Requirements Specification
SRS (Software Requirements Specification) describes what the software must do.


It answers:

> What should the system do?


For example, for a login system:


**Functional requirements:**
> The system shall allow registered users to log in using email and password.
> The system shall reject invalid credentials.
> The system shall prevent inactive users from accessing protected resources.


**Non-functional requirements:**
> The system shall respond within the defined performance requirement.
> Passwords shall not be stored as plain text.


**So SRS defines the requirements and expected behavior of the system.**



## Architecture Specification
ARS is not a universal abbreviation. Depending on the organization, it may mean Architecture Specification, Architectural Requirements Specification, or another internal term.


If we use Architecture Specification, it describes the high-level structure of the system.


It answers:

> How is the system divided into major components, and how do they communicate?


For example:

```
Client
   |
   v
API Gateway
   |
   +---- User Service
   |
   +---- Order Service
            |
            v
        Database
```


Architecture may describe:
- Major components
- System boundaries
- Communication between components
- Data flow
- External systems
- Deployment structure
- Architectural constraints


The important distinction is:

**SRS:**
> The user must be able to log in.

**Architecture:**
> Authentication is handled by an Authentication Service connected to the User Database.


**Architecture turns requirements into a system structure.**



## Detailed Design Specification
DDS (Detailed Design Specification) usually describes the detailed design of the system.


It answers:
> How exactly will each part of the system work?


For example, the architecture might say:

```
Client
   ↓
Authentication Service
   ↓
User Database
```


The DDS can go deeper:

```
POST /login

Input:
- email
- password

Process:
1. Validate input
2. Find user
3. Verify password
4. Check account status
5. Create session/token
6. Return response
```


It can describe:
- Classes
- Modules
- APIs
- Database structures
- Algorithms
- Interfaces
- Error handling
- Sequence flows
- Component interactions


The simple difference is:

**ARS = High-level design**

**DDS = Detailed design**


## Configuration Management
Configuration Management (CM) is the process of controlling and tracking changes to software and project artifacts.

It answers:
> What version are we using, what changed, who changed it, and is the change controlled?

Configuration items can include:
- Source code
- Requirements
- Architecture documents
- Configuration files
- Dependencies
- Infrastructure
- Test artifacts
- Release packages

For example:
```
Version 1.0
     ↓
Change Request
     ↓
Review
     ↓
Implementation
     ↓
Testing
     ↓
Version 1.1
```

Git is commonly used as part of configuration management.

The purpose is to prevent uncontrolled changes and make changes traceable and reproducible.
