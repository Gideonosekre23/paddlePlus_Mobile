import React from "react";
import { Home, History, Settings, ExitToApp } from "@mui/icons-material";

const RiderNav = ({ isExpanded }) => {
  return (
    <ul className="nav-options">
      <li>
        <Home />
        {isExpanded && <span>Home</span>}
      </li>
      <li>
        <History />
        {isExpanded && <span>History</span>}
      </li>
      <li>
        <Settings />
        {isExpanded && <span>Settings</span>}
      </li>
      <li className="logout">
        <ExitToApp />
        {isExpanded && <span>Log Out</span>}
      </li>
    </ul>
  );
};

export default RiderNav;
