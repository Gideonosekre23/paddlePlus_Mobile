import React, { useState } from "react";
import OwnerNav from "./OwnerNav";
import RiderNav from "./RiderNav";
import "../styles/NavBar.css";

const NavBar = ({ userType }) => {
  const [isExpanded, setIsExpanded] = useState(false);

  const handleMouseEnter = () => {
    setIsExpanded(true);
  };

  const handleMouseLeave = () => {
    setIsExpanded(false);
  };

  return (
    <div
      className={`nav-bar ${isExpanded ? "expanded" : "retracted"}`}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      {userType === "owner" ? <OwnerNav isExpanded={isExpanded} /> : <RiderNav isExpanded={isExpanded} />}
    </div>
  );
};

export default NavBar;