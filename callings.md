Ward Callings App

Write an iPadOS application to manage callings for a ward in the Church of Jesus Christ of Latter-day Saints. Work from an iPad or a 16:9 TV/projector.  Write the code, save in GitHub and compile and send to TestFlight the same method I use in the habits projects.

See this link https://www.churchofjesuschrist.org/study/manual/general-handbook?lang=eng#map38 for an overview of the calling and release process.

The app must read pdf documents that contain the current ward organization (calling and member) and the current list of members without callings. The main page should show the current ward organization by group.  Filters should be available to highlight members that have been in the calling over x months in one color and highlight callings that are empty and need to be filled.

Each calling will have attributes for available candidates (male, female, young woman class, Priesthood, class, etc).

A member may have more than one calling.

When a user selects a calling,  a new entry is created in the Open Callings table that will make that calling appear in the Open Callings View. Here, the user will see a table that shows the following fields.  A calling that has an open entry change from white to red text.

- assigned bishopric member (bishop, 1st counselor, 2nd counselor)
- group (sorted)
- calling (sorted by calling order field so that the President appears first, 1st Counselor, 2nd Counselor, Secretary and other callings in order)
- Member currently called (with a color showing the status of the member to be released)
- Member to be called (with a color showing the status of the member to be called)
- Candidates

When the user taps the candidate list, a popup appears allowing the user to select or more members from a filtered list of candidates. The list should show the name, calling (can be blank if needs calling), and an attribute column that the user can update with a category (blank, not active, etc).  As the user scrolls through the filtered list, they can select the name to identify as a candidate for the calling.  Then close the filtered list to show the candidates

Status of the member to be released
Open - The name of the existing member holding the calling should change to red when the member is selected to be released.
Released - The name of the member changes to blue when the member has been notified of a release
Announced - The color is removed when the member is officially released in sacrament meeting

Status of the member to be called
Selected - The name of the new candidate changes to Yellow when selected to call
Accepted - The name of the candidate changes to Green when the member accepts
Sustained - The color is removed when the member is sustained in the new calling

When the user selects the Open Callings view, they can see the member category (Release/Call), 

If a calling is long-pressed then a menu opens to allow the criteria for members to be edited and the calling display sequence.

Views/Pages
- Ward Callings
    - Filtered list of candidates pop-up
- Open Callings
- Import


Ward Callings Page
Home page is Ward Callings that has 7 groups of 2 columns showing the calling/name for the following groups:
- Bishopric
- Elders Quorum
- Relief Society
- Ward Missionaries
- Temple and Family History
- Sunday School
- Aaronic Priesthood Quorums
- Young Women
- Primary
- Young Single Adult
- Other Callings

It will be displayed on a 16:9 TV, iPad so the table should be flexible.

User selects items to highlight
- Open Callings
- Calling over x months
User can select an organization to drill into or a specific calling to drill into
Organization View (multi calling option)
Calling View (single calling option)

Show 
- org/calling (action can be assigned)
- Candidates (names from Members Need Callings and Members with Callings can be dragged into this column, allow to highlight members)
- Members Need Callings
- Members With Callings (sort by last name or by time in current calling)

Import
- Import the Ward Callings from pdf saved from LCR (lcr.churchofjesuschrist.org)
    - If a new person has been called, then archive and clear the working list
- Import the current list of Members along with filter criteria
- Files located in the /import folder.  Allow the user to select and import both files from the app.
