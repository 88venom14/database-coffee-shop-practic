USE coffee_shop_db;

DROP VIEW IF EXISTS v_order_summary;
CREATE VIEW v_order_summary AS
SELECT o.OrderID,
       c.FullName  AS Customer,
       o.OrderDate,
       o.Status,
       o.TotalAmount
FROM customerorders o
    LEFT JOIN customers c ON o.CustomerID = c.CustomerID;

DROP FUNCTION IF EXISTS fn_order_total;
DELIMITER //
CREATE FUNCTION fn_order_total(p_order_id INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(10,2);
    SELECT COALESCE(SUM(d.Quantity * m.Price), 0)
      INTO v_total
      FROM orderdetails d
      JOIN menu m ON d.MenuID = m.MenuID
     WHERE d.OrderID = p_order_id;
    RETURN v_total;
END //
DELIMITER ;

DROP TRIGGER IF EXISTS trg_recalc_total;
DELIMITER //
CREATE TRIGGER trg_recalc_total
AFTER INSERT ON orderdetails
FOR EACH ROW
BEGIN
    UPDATE customerorders
       SET TotalAmount = fn_order_total(NEW.OrderID)
     WHERE OrderID = NEW.OrderID;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS sp_pay_order;
DELIMITER //
CREATE PROCEDURE sp_pay_order(
    IN  p_order_id INT,
    IN  p_method   ENUM('Cash','Card','Online'),
    OUT p_result   VARCHAR(50))
BEGIN
    DECLARE v_total  DECIMAL(10,2);
    DECLARE v_paid   INT DEFAULT 0;
    DECLARE v_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'Ошибка: платёж отменён';
    END;

    START TRANSACTION;
        SELECT Status INTO v_status
          FROM customerorders WHERE OrderID = p_order_id;
        SELECT COUNT(*) INTO v_paid
          FROM payments WHERE OrderID = p_order_id;

        IF v_status = 'Cancelled' OR v_paid > 0 THEN
            SET p_result = 'Оплата невозможна';
            ROLLBACK;
        ELSE
            SET v_total = fn_order_total(p_order_id);
            INSERT INTO payments(OrderID, Amount, PaymentMethod)
            VALUES (p_order_id, v_total, p_method);
            UPDATE customerorders SET Status = 'Completed'
             WHERE OrderID = p_order_id;
            COMMIT;
            SET p_result = 'Оплачено';
        END IF;
END //
DELIMITER ;

CREATE ROLE IF NOT EXISTS 'coffee_admin', 'coffee_cashier';

GRANT ALL PRIVILEGES ON coffee_shop_db.* TO 'coffee_admin';

GRANT SELECT ON coffee_shop_db.menu TO 'coffee_cashier';
GRANT SELECT, INSERT, UPDATE ON coffee_shop_db.customerorders TO 'coffee_cashier';
GRANT SELECT, INSERT ON coffee_shop_db.orderdetails TO 'coffee_cashier';
GRANT EXECUTE ON PROCEDURE coffee_shop_db.sp_pay_order TO 'coffee_cashier';
