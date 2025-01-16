import React from "react";
import { Home, Map, Settings, ExitToApp } from "@mui/icons-material";

const OwnerNav = ({ isExpanded }) => {
  return (
    <ul className="nav-options">
      <li>
        <Home />
        {isExpanded && <span>Home</span>}
      </li>
      <li>
        <Map />
        {isExpanded && <span>Map</span>}
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

export default OwnerNav;